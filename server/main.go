package main

import (
	"flag"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// LittleLaw Rendezvous:可选的公网中转/信令服务器。
// 设计原则:服务器是"瞎子"——不持有任何私钥,只见设备 ID 与密文。
// 没有它,LittleLaw 全部局域网/WebRTC 功能照常运行。

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	// 原生客户端(Dart)不发 Origin 头:无 Origin 一律放行;
	// 带 Origin 的请求(网页)必须在白名单内——否则网页可用受害者 IP
	// 消耗建连令牌(定向连接饥饿)。
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		return allowedOrigins[origin]
	},
}

var allowedOrigins = map[string]bool{}

func main() {
	addr := flag.String("addr", ":47600", "监听地址")
	dbPath := flag.String("db", "rendezvous.db", "邮箱数据库文件路径")
	fcmKey := flag.String("fcm-key", "", "Firebase serviceAccount.json 路径(可选,启用离线推送唤醒)")
	maxConns := flag.Int("max-conns", 4096, "全局并发连接上限")
	connBurst := flag.Int("conn-burst", 30, "每 IP 每分钟新建连接数上限")
	msgBurst := flag.Int("msg-burst", 200, "每连接/每设备 10 秒消息数上限(防刷屏)")
	origins := flag.String("allowed-origins", "", "允许的浏览器 Origin 列表(逗号分隔;空 = 拒绝全部浏览器来源,原生客户端不受影响)")
	flag.Parse()
	for _, o := range strings.Split(*origins, ",") {
		if o = strings.TrimSpace(o); o != "" {
			allowedOrigins[o] = true
		}
	}

	mb, err := OpenMailbox(*dbPath)
	if err != nil {
		log.Fatalf("open mailbox: %v", err)
	}
	defer mb.Close()

	push := NewPushService(mb.db, *fcmKey)
	registry := NewRegistry(mb.db)
	hub := NewHub()
	limiter := NewLimiter(*maxConns, *connBurst, *msgBurst)

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		// 建连准入:IP 令牌桶 + 全局并发上限。
		if !limiter.AllowConn(r) {
			writeTooMany(w)
			return
		}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			limiter.ConnClosed()
			log.Printf("upgrade: %v", err)
			return
		}
		client := newClient(hub, mb, push, registry, conn, limiter)
		go client.writePump()
		go client.readPump()
	})

	server := &http.Server{
		Addr:              *addr,
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("littlelaw-rendezvous listening on %s (db=%s)", *addr, *dbPath)
	log.Fatal(server.ListenAndServe())
}
