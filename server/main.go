package main

import (
	"flag"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

// LittleLaw Rendezvous:可选的公网中转/信令服务器。
// 设计原则:服务器是"瞎子"——不持有任何私钥,只见设备 ID 与密文。
// 没有它,LittleLaw 全部局域网/WebRTC 功能照常运行。

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	// 开发期放开来源检查(生产可收紧)。
	CheckOrigin: func(r *http.Request) bool { return true },
}

func main() {
	addr := flag.String("addr", ":47600", "监听地址")
	dbPath := flag.String("db", "rendezvous.db", "邮箱数据库文件路径")
	fcmKey := flag.String("fcm-key", "", "Firebase serviceAccount.json 路径(可选,启用离线推送唤醒)")
	flag.Parse()

	mb, err := OpenMailbox(*dbPath)
	if err != nil {
		log.Fatalf("open mailbox: %v", err)
	}
	defer mb.Close()

	push := NewPushService(mb.db, *fcmKey)
	hub := NewHub()

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("upgrade: %v", err)
			return
		}
		client := newClient(hub, mb, push, conn)
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
