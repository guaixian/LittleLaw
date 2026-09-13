package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"go.etcd.io/bbolt"
)

// 离线邮箱:bbolt 持久化。根 bucket "mailbox",每个接收方一个子 bucket,
// 顺序自增 key,值为 JSON{from,data}。服务器只见密文。
//
// 配额:每箱最多 [boxCap] 条 / [boxBytesCap] 字节,全库合计 [totalBytesCap]
// 字节。超限拒收(ErrBoxFull / ErrTotalFull),防刷爆磁盘。
type Mailbox struct {
	db             *bbolt.DB
	boxCap         int
	boxBytesCap    int64
	totalBytesCap  int64
	metaBucket     []byte
	totalBytes     int64
	totalBytesOnce sync.Once
}

var (
	mailboxBucket = []byte("mailbox")
	metaBucketKey = []byte("__meta__")
	totalBytesKey = []byte("total_bytes")
)

// ErrBoxFull 单个邮箱已满(收件方长期不上线拉取)。
var ErrBoxFull = errors.New("mailbox of recipient is full")

// ErrTotalFull 全库配额用尽(服务器管理员需扩容)。
var ErrTotalFull = errors.New("server mailbox storage is full")

func OpenMailbox(path string) (*Mailbox, error) {
	db, err := bbolt.Open(path, 0o600, &bbolt.Options{Timeout: 2 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("open mailbox db: %w", err)
	}
	return &Mailbox{
		db:            db,
		boxCap:        500,             // 每箱最多 500 封
		boxBytesCap:   16 << 20,        // 每箱 16 MiB
		totalBytesCap: 2 << 30,         // 全库 2 GiB
		metaBucket:    metaBucketKey,
	}, nil
}

func (m *Mailbox) Close() error { return m.db.Close() }

type mailRecord struct {
	From string `json:"from"`
	Data string `json:"data"`
}

// 投递一封(返回序号)。超配额返回 ErrBoxFull / ErrTotalFull。
func (m *Mailbox) Push(to, from, data string) (uint64, error) {
	var id uint64
	rec, _ := json.Marshal(mailRecord{From: from, Data: data})
	recBytes := int64(len(rec))
	if len(data) > 256<<10 {
		// 单封密文上限 256 KiB(协议信封远小于此,防超大载荷刷库)。
		return 0, ErrBoxFull
	}
	// 全库字节数懒加载(首次 Push 时统计一次)。
	m.totalBytesOnce.Do(func() {
		var total int64
		_ = m.db.View(func(tx *bbolt.Tx) error {
			root := tx.Bucket(mailboxBucket)
			if root == nil {
				return nil
			}
			_ = root.ForEach(func(k, v []byte) error {
				if v == nil { // 子桶
					total += int64(root.Bucket(k).Stats().KeyN) * 32 // 粗估
				}
				return nil
			})
			return nil
		})
		m.totalBytes = total
	})
	err := m.db.Update(func(tx *bbolt.Tx) error {
		root, err := tx.CreateBucketIfNotExists(mailboxBucket)
		if err != nil {
			return err
		}
		box, err := root.CreateBucketIfNotExists([]byte(to))
		if err != nil {
			return err
		}
		// 配额检查。
		stats := box.Stats()
		boxBytes := int64(stats.BranchInuse + stats.LeafInuse + stats.BucketN*16)
		if stats.KeyN >= m.boxCap {
			return ErrBoxFull
		}
		if boxBytes+recBytes > m.boxBytesCap {
			return ErrBoxFull
		}
		if m.totalBytes+recBytes > m.totalBytesCap {
			return ErrTotalFull
		}
		seq, err := box.NextSequence()
		if err != nil {
			return err
		}
		id = seq
		var key [8]byte
		binary.BigEndian.PutUint64(key[:], seq)
		if err := box.Put(key[:], rec); err != nil {
			return err
		}
		m.totalBytes += recBytes
		meta, err := tx.CreateBucketIfNotExists(m.metaBucket)
		if err != nil {
			return err
		}
		var tb [8]byte
		binary.BigEndian.PutUint64(tb[:], uint64(m.totalBytes))
		return meta.Put(totalBytesKey, tb[:])
	})
	return id, err
}

// 拉取全部(最多 limit 条)。
func (m *Mailbox) Fetch(to string, limit int) ([]MailboxItem, error) {
	var items []MailboxItem
	err := m.db.View(func(tx *bbolt.Tx) error {
		root := tx.Bucket(mailboxBucket)
		if root == nil {
			return nil
		}
		box := root.Bucket([]byte(to))
		if box == nil {
			return nil
		}
		c := box.Cursor()
		for k, v := c.First(); k != nil && len(items) < limit; k, v = c.Next() {
			var rec mailRecord
			if err := json.Unmarshal(v, &rec); err != nil {
				continue
			}
			items = append(items, MailboxItem{
				ID:   binary.BigEndian.Uint64(k),
				From: rec.From,
				Data: rec.Data,
			})
		}
		return nil
	})
	return items, err
}

// 确认删除(回收配额)。
func (m *Mailbox) Ack(to string, ids []uint64) error {
	var freed int64
	err := m.db.Update(func(tx *bbolt.Tx) error {
		root := tx.Bucket(mailboxBucket)
		if root == nil {
			return errors.New("no mailbox")
		}
		box := root.Bucket([]byte(to))
		if box == nil {
			return nil
		}
		for _, id := range ids {
			var key [8]byte
			binary.BigEndian.PutUint64(key[:], id)
			if v := box.Get(key[:]); v != nil {
				freed += int64(len(v))
			}
			if err := box.Delete(key[:]); err != nil {
				return err
			}
		}
		// 空桶回收。
		if box.Stats().KeyN == 0 {
			return root.DeleteBucket([]byte(to))
		}
		return nil
	})
	if err != nil {
		return err
	}
	if freed > 0 {
		m.totalBytes -= freed
		if m.totalBytes < 0 {
			m.totalBytes = 0
		}
		_ = m.db.Update(func(tx *bbolt.Tx) error {
			meta, err := tx.CreateBucketIfNotExists(m.metaBucket)
			if err != nil {
				return err
			}
			var tb [8]byte
			binary.BigEndian.PutUint64(tb[:], uint64(m.totalBytes))
			return meta.Put(totalBytesKey, tb[:])
		})
	}
	return nil
}
