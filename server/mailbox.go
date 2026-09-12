package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"go.etcd.io/bbolt"
)

// 离线邮箱:bbolt 持久化。根 bucket "mailbox",每个接收方一个子 bucket,
// 顺序自增 key,值为 JSON{from,data}。服务器只见密文。
type Mailbox struct {
	db *bbolt.DB
}

var mailboxBucket = []byte("mailbox")

func OpenMailbox(path string) (*Mailbox, error) {
	db, err := bbolt.Open(path, 0o600, &bbolt.Options{Timeout: 2 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("open mailbox db: %w", err)
	}
	return &Mailbox{db: db}, nil
}

func (m *Mailbox) Close() error { return m.db.Close() }

type mailRecord struct {
	From string `json:"from"`
	Data string `json:"data"`
}

// 投递一封(返回序号)。
func (m *Mailbox) Push(to, from, data string) (uint64, error) {
	var id uint64
	rec, _ := json.Marshal(mailRecord{From: from, Data: data})
	err := m.db.Update(func(tx *bbolt.Tx) error {
		root, err := tx.CreateBucketIfNotExists(mailboxBucket)
		if err != nil {
			return err
		}
		box, err := root.CreateBucketIfNotExists([]byte(to))
		if err != nil {
			return err
		}
		seq, err := box.NextSequence()
		if err != nil {
			return err
		}
		id = seq
		var key [8]byte
		binary.BigEndian.PutUint64(key[:], seq)
		return box.Put(key[:], rec)
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

// 确认删除。
func (m *Mailbox) Ack(to string, ids []uint64) error {
	return m.db.Update(func(tx *bbolt.Tx) error {
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
}
