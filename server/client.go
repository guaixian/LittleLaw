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
	endpoint string
	authed   bool
	limiter  *Limiter
	msgs     msgWindow // 每客户端消息窗口(防刷屏)

	closeOnce sync.Once
}

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = 45 * time.Second
	maxMessageSize = 1 << 20 // 1 MiB
	authTimeout    = 15 * time.Second
	maxSubscribe   = 512     // 单连接订阅设备数上限
)

func newClient(h *Hub, mb *Mailbox, push *PushService, conn *websocket.Conn, limiter *Limiter) *Client {
	return &Client{
		hub:     h,
		mailbox: mb,
		push:    push,
		conn:    conn,
		send:    make(chan []byte, 64),
		limiter: limiter,
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
		c.limiter.ConnClosed()
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
	c.endpoint = hello.Endpoint
	c.authed = true
	c.hub.register(c)
	c.sendJSON(HelloOKFrame{Type: "hello_ok", ServerTime: time.Now().UnixMilli()})
	return true
}

func (c *Client) handleFrame(message []byte) {
	// 每客户端滑动窗口:10 秒 200 帧,超限断连(刷屏攻击者直接踢)。
	if !c.msgs.allow(c.limiter.msgWindow, c.limiter.msgBurst) {
		c.sendJSON(ErrorFrame{Type: "error", Message: "rate limit exceeded"})
		c.kick()
		return
	}
	var f Frame
	if err := json.Unmarshal(message, &f); err != nil {
		return
	}
	switch f.Type {
	case "subscribe":
		var sub SubscribeFrame
		if json.Unmarshal(message, &sub) == nil {
			if len(sub.IDs) > maxSubscribe {
				sub.IDs = sub.IDs[:maxSubscribe]
			}
			c.hub.subscribe(c, sub.IDs)
		}
	case "signal":
		var sig SignalFromClientFrame
		if json.Unmarshal(message, &sig) == nil && sig.To != "" && len(sig.Data) <= 256<<10 {
			if !c.hub.forwardTo(sig.To, SignalToClientFrame{
				Type: "signal", From: c.deviceID, Data: sig.Data,
			}) {
				c.sendJSON(ErrorFrame{Type: "error", Message: "peer offline"})
			}
		}
	case "mailbox_push":
		var push MailboxPushFrame
		if json.Unmarshal(message, &push) == nil && push.To != "" {
			id, err := c.mailbox.Push(push.To, c.deviceID, push.Data)
			switch {
			case err == ErrBoxFull:
				c.sendJSON(ErrorFrame{Type: "error",
					Message: "mailbox of " + push.To + " is full (recipient must come online)"})
			case err == ErrTotalFull:
				c.sendJSON(ErrorFrame{Type: "error", Message: "server mailbox storage is full"})
			case err != nil:
				log.Printf("mailbox push: %v", err)
			default:
				if c.hub.isOnline(push.To) {
					// 收件人在线:立即直投这一封(与稍后轮询重复,按 msg_id 幂等)。
					c.hub.deliverJSON(push.To, MailboxFrame{
						Type:  "mailbox",
						Items: []MailboxItem{{ID: id, From: c.deviceID, Data: push.Data}},
					})
				} else {
					// 接收方离线:代发推送唤醒(仅信号,无内容)。
					c.push.NotifyDevice(push.To)
				}
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
