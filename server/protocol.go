package main

// 协议帧(WS JSON 文本消息)。
// 方向:C→S 客户端到服务端;S→C 服务端到客户端。

// 通用帧(解码时先读 type)。
type Frame struct {
	Type string `json:"type"`
}

// ---- S→C ----

type ChallengeFrame struct {
	Type  string `json:"type"` // "challenge"
	Nonce string `json:"nonce"`
}

type HelloOKFrame struct {
	Type       string `json:"type"` // "hello_ok"
	ServerTime int64  `json:"serverTime"`
}

type ErrorFrame struct {
	Type    string `json:"type"` // "error"
	Message string `json:"message"`
}

type PresenceFrame struct {
	Type    string   `json:"type"` // "presence"
	Online  []string `json:"online"`
	Offline []string `json:"offline"`
}

type PeerEventFrame struct {
	Type string `json:"type"` // "peer_online" / "peer_offline"
	ID   string `json:"id"`
}

type SignalToClientFrame struct {
	Type string `json:"type"` // "signal"
	From string `json:"from"`
	Data string `json:"data"` // 密文(base64)
}

type MailboxItem struct {
	ID   uint64 `json:"id"`
	From string `json:"from"`
	Data string `json:"data"` // 密文(base64)
}

type MailboxFrame struct {
	Type  string        `json:"type"` // "mailbox"
	Items []MailboxItem `json:"items"`
}

// ---- C→S ----

type HelloFrame struct {
	Type        string `json:"type"` // "hello"
	DeviceID    string `json:"deviceId"`
	Fingerprint string `json:"fingerprint"`
	CertPEM     string `json:"cert"`
	Sig         string `json:"sig"` // hex(r||s),对 sha256(deviceId|fingerprint|nonce) 的 ECDSA 签名
}

type SubscribeFrame struct {
	Type string   `json:"type"` // "subscribe"
	IDs  []string `json:"ids"`
}

type SignalFromClientFrame struct {
	Type string `json:"type"` // "signal"
	To   string `json:"to"`
	Data string `json:"data"`
}

type MailboxPushFrame struct {
	Type string `json:"type"` // "mailbox_push"
	To   string `json:"to"`
	Data string `json:"data"`
}

type MailboxFetchFrame struct {
	Type string `json:"type"` // "mailbox_fetch"
}

type MailboxAckFrame struct {
	Type string   `json:"type"` // "mailbox_ack"
	IDs  []uint64 `json:"ids"`
}

type PushRegisterFrame struct {
	Type     string `json:"type"` // "push_register"
	Token    string `json:"token"`
	Platform string `json:"platform"` // android / ios
}
