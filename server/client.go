package main

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// 单个 WS 连接(未认证 → 已认证设备)。
type Client struct {
	hub      *Hub
	mailbox  *Mailbox
	push     *PushService
	conn     *websocket.Conn
	send     chan []byte
	deviceID string
	nonce    string
	authed   bool

	closeOnce sync.Once
}

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = 45 * time.Second
	maxMessageSize = 1 << 20 // 1 MiB
	authTimeout    = 15 * time.Second
)

func newClient(h *Hub, mb *Mailbox, push *PushService, conn *websocket.Conn) *Client {
	return &Client{
		hub:     h,
		mailbox: mb,
		push:    push,
		conn:    conn,
		send:    make(chan []byte, 64),
	}
}

func (c *Client) sendJSON(v any) bool {
	data, err := json.Marshal(v)
	if err != nil {
		return false
	}
	select {
	case c.send <- data:
		return true
	default:
		// 发送缓冲满:慢消费者,断开。
		c.kick()
		return false
	}
}

func (c *Client) kick() {
	c.closeOnce.Do(func() {
		close(c.send)
	})
}

// 读泵:挑战 → 认证 → 消息分发。
func (c *Client) readPump() {
	defer func() {
		if c.authed {
			c.hub.unregister(c)
		}
		c.conn.Close()
	}()

	// 1) 发挑战。
	nonce, err := newNonce()
	if err != nil {
		return
	}
	c.nonce = nonce
	if !c.sendJSON(ChallengeFrame{Type: "challenge", Nonce: nonce}) {
		return
	}

	c.conn.SetReadLimit(maxMessageSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		if !c.authed {
			_ = c.conn.SetReadDeadline(time.Now().Add(authTimeout))
			if !c.handleHello(message) {
				return
			}
			continue
		}
		c.handleFrame(message)
	}
}

func (c *Client) handleHello(message []byte) bool {
	var hello HelloFrame
	if err := json.Unmarshal(message, &hello); err != nil || hello.Type != "hello" {
		c.sendJSON(ErrorFrame{Type: "error", Message: "expect hello"})
		return false
	}
	if err := verifyHello(hello.DeviceID, hello.Fingerprint, hello.CertPEM, hello.Sig, c.nonce); err != nil {
		c.sendJSON(ErrorFrame{Type: "error", Message: "auth failed: " + err.Error()})
		return false
	}
	c.deviceID = hello.DeviceID
	c.authed = true
	c.hub.register(c)
	c.sendJSON(HelloOKFrame{Type: "hello_ok", ServerTime: time.Now().UnixMilli()})
	return true
}

func (c *Client) handleFrame(message []byte) {
	var f Frame
	if err := json.Unmarshal(message, &f); err != nil {
		return
	}
	switch f.Type {
	case "subscribe":
		var sub SubscribeFrame
		if json.Unmarshal(message, &sub) == nil {
			c.hub.subscribe(c, sub.IDs)
		}
	case "signal":
		var sig SignalFromClientFrame
		if json.Unmarshal(message, &sig) == nil && sig.To != "" {
			if !c.hub.forwardTo(sig.To, SignalToClientFrame{
				Type: "signal", From: c.deviceID, Data: sig.Data,
			}) {
				c.sendJSON(ErrorFrame{Type: "error", Message: "peer offline"})
			}
		}
	case "mailbox_push":
		var push MailboxPushFrame
		if json.Unmarshal(message, &push) == nil && push.To != "" {
			if _, err := c.mailbox.Push(push.To, c.deviceID, push.Data); err != nil {
				log.Printf("mailbox push: %v", err)
			} else if !c.hub.isOnline(push.To) {
				// 接收方离线:代发推送唤醒(仅信号,无内容)。
				c.push.NotifyDevice(push.To)
			}
		}
	case "push_register":
		var reg PushRegisterFrame
		if json.Unmarshal(message, &reg) == nil && reg.Token != "" {
			if err := c.push.saveToken(c.deviceID, reg.Token, reg.Platform); err != nil {
				log.Printf("push register: %v", err)
			}
		}
	case "mailbox_fetch":
		items, err := c.mailbox.Fetch(c.deviceID, 500)
		if err != nil {
			log.Printf("mailbox fetch: %v", err)
			return
		}
		if items == nil {
			items = []MailboxItem{}
		}
		c.sendJSON(MailboxFrame{Type: "mailbox", Items: items})
	case "mailbox_ack":
		var ack MailboxAckFrame
		if json.Unmarshal(message, &ack) == nil {
			if err := c.mailbox.Ack(c.deviceID, ack.IDs); err != nil {
				log.Printf("mailbox ack: %v", err)
			}
		}
	}
}

// 写泵:心跳 + 发件。
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case message, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage,
					websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
