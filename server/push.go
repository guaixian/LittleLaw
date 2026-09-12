package main

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"go.etcd.io/bbolt"
	"google.golang.org/api/option"
)

// FCM 唤醒:设备注册推送令牌;收到发给【离线】设备的信封时,
// 代发一条 FCM 数据消息(仅唤醒信号,绝不含任何消息内容)。
// 未配置 serviceAccount.json 时整体静默禁用,不影响其他功能。

var pushBucket = []byte("pushtokens")

type pushRecord struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
	AtMs     int64  `json:"atMs"`
}

type PushService struct {
	db     *bbolt.DB
	msg    *messaging.Client
	mu     sync.Mutex
	notify chan string
}

func NewPushService(db *bbolt.DB, fcmKeyPath string) *PushService {
	p := &PushService{db: db, notify: make(chan string, 256)}

	if fcmKeyPath != "" {
		ctx := context.Background()
		app, err := firebase.NewApp(ctx, nil, option.WithCredentialsFile(fcmKeyPath))
		if err != nil {
			log.Printf("fcm: init disabled (%v)", err)
		} else if mc, err := app.Messaging(ctx); err != nil {
			log.Printf("fcm: messaging disabled (%v)", err)
		} else {
			p.msg = mc
			log.Printf("fcm: enabled (key=%s)", fcmKeyPath)
		}
	}

	go p.worker()
	return p
}

func (p *PushService) saveToken(deviceID, token, platform string) error {
	rec, _ := json.Marshal(pushRecord{
		Token: token, Platform: platform, AtMs: time.Now().UnixMilli(),
	})
	return p.db.Update(func(tx *bbolt.Tx) error {
		root, err := tx.CreateBucketIfNotExists(pushBucket)
		if err != nil {
			return err
		}
		return root.Put([]byte(deviceID), rec)
	})
}

func (p *PushService) tokenOf(deviceID string) *pushRecord {
	var rec pushRecord
	_ = p.db.View(func(tx *bbolt.Tx) error {
		root := tx.Bucket(pushBucket)
		if root == nil {
			return nil
		}
		if v := root.Get([]byte(deviceID)); v != nil {
			_ = json.Unmarshal(v, &rec)
		}
		return nil
	})
	if rec.Token == "" {
		return nil
	}
	return &rec
}

// 异步通知(不阻塞邮箱投递主路径)。
func (p *PushService) NotifyDevice(deviceID string) {
	select {
	case p.notify <- deviceID:
	default:
	}
}

func (p *PushService) worker() {
	for deviceID := range p.notify {
		if p.msg == nil {
			continue
		}
		rec := p.tokenOf(deviceID)
		if rec == nil {
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		_, err := p.msg.Send(ctx, &messaging.Message{
			Token: rec.Token,
			// 只带唤醒信号,不带任何内容(隐私)。
			Data: map[string]string{"action": "sync"},
			Android: &messaging.AndroidConfig{
				Priority: "high", // 高优先级:允许后台唤醒
			},
			APNS: &messaging.APNSConfig{
				Headers: map[string]string{"apns-priority": "10"},
			},
		})
		cancel()
		if err != nil {
			log.Printf("fcm: send to %s failed: %v", deviceID, err)
		}
	}
}
