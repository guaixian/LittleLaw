package main

import (
	"encoding/json"
	"log"
	"net"
	"regexp"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// 单个 WS 连接(未认证 → 已认证设备)。
type Client struct {
	hub      *Hub
	mailbox  *Mailbox
	push     *PushService
	registry *Registry
	conn     *websocket.Conn
	send     chan []byte
	done     chan struct{} // 关闭 = 本连接已被踢/废弃,禁止再发送
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
	fetchPageSize  = 50      // 邮箱单次拉取上限(防一次返回整箱的内存放大)
)

var deviceIDRe = regexp.MustCompile(`^[0-9a-zA-Z-]{1,64}$`)
var fingerprintRe = regexp.MustCompile(`^[0-9a-f]{64}$`)

// FCM 令牌:可见 ASCII,排除控制字符。
var tokenRe = regexp.MustCompile(`^[\x21-\x7e]+$`)

func newClient(h *Hub, mb *Mailbox, push *PushService, reg *Registry, conn *websocket.Conn, limiter *Limiter) *Client {
	return &Client{
		hub:      h,
		mailbox:  mb,
		push:     push,
		registry: reg,
		conn:     conn,
		send:     make(chan []byte, 64),
		done:     make(chan struct{}),
		limiter:  limiter,
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
	case <-c.done:
		// 连接已废弃:不再发送(往已关闭通道发送会 panic 整个进程)。
		return false
	default:
		// 发送缓冲满:慢消费者,断开。
		c.kick()
		return false
	}
}

func (c *Client) kick() {
	// 只关闭 done 信号,不关闭 send 通道:在途的 hub 广播/直投还可能
	// 调用 sendJSON,关闭通道会导致 send-on-closed-channel panic。
	c.closeOnce.Do(func() {
		close(c.done)
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
			// hello 成功后立即续期读 deadline:旧版停在 now+15s,
			// 空闲已认证连接 ~15s 必被误杀(首个 ping 要 45s 后才发),
			// 造成周期性"断开→重连"与 presence 抖动。
			_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
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
	// 输入校验:deviceID/指纹格式与长度(endpoint 原样进入 presence
	// 广播,恶意超大值会被复制给所有关注者形成带宽放大)。
	if !deviceIDRe.MatchString(hello.DeviceID) {
		c.sendJSON(ErrorFrame{Type: "error", Message: "invalid deviceId"})
		return false
	}
	if !fingerprintRe.MatchString(hello.Fingerprint) {
		c.sendJSON(ErrorFrame{Type: "error", Message: "invalid fingerprint"})
		return false
	}
	if hello.Endpoint != "" {
		if len(hello.Endpoint) > 260 {
			c.sendJSON(ErrorFrame{Type: "error", Message: "endpoint too long"})
			return false
		}
		if _, _, err := net.SplitHostPort(hello.Endpoint); err != nil {
			c.sendJSON(ErrorFrame{Type: "error", Message: "invalid endpoint"})
			return false
		}
	}
	if err := verifyHello(hello.DeviceID, hello.Fingerprint, hello.CertPEM, hello.Sig, c.nonce); err != nil {
		c.sendJSON(ErrorFrame{Type: "error", Message: "auth failed: " + err.Error()})
		return false
	}
	// TOFU 登记:同一 deviceID 只能绑定首见指纹(防冒充/踢线/信箱窃取)。
	if c.registry != nil {
		if err := c.registry.Register(hello.DeviceID, hello.Fingerprint); err != nil {
			c.sendJSON(ErrorFrame{Type: "error", Message: "identity conflict: " + err.Error()})
			return false
		}
	}
	c.deviceID = hello.DeviceID
	c.endpoint = hello.Endpoint
	c.authed = true
	c.hub.register(c)
	c.sendJSON(HelloOKFrame{Type: "hello_ok", ServerTime: time.Now().UnixMilli()})
	return true
}

func (c *Client) handleFrame(message []byte) {
	// 双层窗口:连接级 + 设备级(换连接重置连接级额度的重连风暴
	// 仍受设备级窗口约束)。
	if !c.msgs.allow(c.limiter.msgWindow, c.limiter.msgBurst) ||
		!c.limiter.msgAllowDevice(c.deviceID) {
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
			// FCM 令牌校验:长度与字符集(可被任意连接覆盖任意设备的
			// 面,至少不让垃圾值进库)。
			if len(reg.Token) > 4096 || !tokenRe.MatchString(reg.Token) {
				c.sendJSON(ErrorFrame{Type: "error", Message: "invalid push token"})
				return
			}
			if err := c.push.saveToken(c.deviceID, reg.Token, reg.Platform); err != nil {
				log.Printf("push register: %v", err)
			}
		}
	case "mailbox_fetch":
		// 分页:每次最多 fetchPageSize 封(旧版一次整箱 ≤500 封/16MiB,
		// 限频窗口内可达数百 MB/s 的序列化+GC 放大)。客户端 ACK 后
		// 下一次轮询自然拿到下一页。
		items, err := c.mailbox.Fetch(c.deviceID, fetchPageSize)
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
		case message := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-c.done:
			_ = c.conn.WriteMessage(websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
			return
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
