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
//
// 配额:每箱最多 [boxCap] 条 / [boxBytesCap] 字节,全库合计 [totalBytesCap]
// 字节。超限拒收(ErrBoxFull / ErrTotalFull),防刷爆磁盘。
//
// 记账:总字节数存在 __meta__/total_bytes,读写都在同一个 bbolt Update
// 事务里(bbolt 单写者串行,天然免锁)——旧版 Push 加/ Ack 减跨事务
// 无锁读改写存在竞争(go test -race 必报),计数丢失更新可绕过配额;
// 重启后的初始值也由精确遍历求和得出(旧版按"每封 32B"估算,
// 实际单封最大 ~350KB,重启后计数几乎归零,2GiB 上限形同虚设)。
type Mailbox struct {
	db            *bbolt.DB
	boxCap        int
	boxBytesCap   int64
	totalBytesCap int64
	metaBucket    []byte
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
	m := &Mailbox{
		db:            db,
		boxCap:        500,      // 每箱最多 500 封
		boxBytesCap:   16 << 20, // 每箱 16 MiB
		totalBytesCap: 2 << 30,  // 全库 2 GiB
		metaBucket:    metaBucketKey,
	}
	if err := m.recountTotal(); err != nil {
		db.Close()
		return nil, fmt.Errorf("mailbox recount: %w", err)
	}
	return m, nil
}

// recountTotal 启动时精确遍历求和(含每条记录的存储开销),
// 写入 meta 作为后续事务内记账的基线。
func (m *Mailbox) recountTotal() error {
	return m.db.Update(func(tx *bbolt.Tx) error {
		var total int64
		root := tx.Bucket(mailboxBucket)
		if root != nil {
			_ = root.ForEach(func(k, v []byte) error {
				if v == nil { // 子桶
					b := root.Bucket(k)
					st := b.Stats()
					total += int64(st.BranchInuse + st.LeafInuse)
					_ = b.ForEach(func(_, mv []byte) error {
						total += int64(len(mv))
						return nil
					})
				}
				return nil
			})
		}
		meta, err := tx.CreateBucketIfNotExists(m.metaBucket)
		if err != nil {
			return err
		}
		var tb [8]byte
		binary.BigEndian.PutUint64(tb[:], uint64(total))
		return meta.Put(totalBytesKey, tb[:])
	})
}

func (m *Mailbox) Close() error { return m.db.Close() }

type mailRecord struct {
	From string `json:"from"`
	Data string `json:"data"`
}

func (m *Mailbox) readTotalLocked(tx *bbolt.Tx) int64 {
	meta := tx.Bucket(m.metaBucket)
	if meta == nil {
		return 0
	}
	if v := meta.Get(totalBytesKey); v != nil && len(v) == 8 {
		return int64(binary.BigEndian.Uint64(v))
	}
	return 0
}

func (m *Mailbox) writeTotalLocked(tx *bbolt.Tx, total int64) error {
	meta, err := tx.CreateBucketIfNotExists(m.metaBucket)
	if err != nil {
		return err
	}
	var tb [8]byte
	binary.BigEndian.PutUint64(tb[:], uint64(total))
	return meta.Put(totalBytesKey, tb[:])
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
	err := m.db.Update(func(tx *bbolt.Tx) error {
		root, err := tx.CreateBucketIfNotExists(mailboxBucket)
		if err != nil {
			return err
		}
		box, err := root.CreateBucketIfNotExists([]byte(to))
		if err != nil {
			return err
		}
		// 配额检查(总数在同一事务内读取,单写者串行 = 无竞争)。
		stats := box.Stats()
		boxBytes := int64(stats.BranchInuse + stats.LeafInuse + stats.BucketN*16)
		if stats.KeyN >= m.boxCap {
			return ErrBoxFull
		}
		if boxBytes+recBytes > m.boxBytesCap {
			return ErrBoxFull
		}
		total := m.readTotalLocked(tx)
		if total+recBytes > m.totalBytesCap {
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
		return m.writeTotalLocked(tx, total+recBytes)
	})
	return id, err
}

// 拉取(最多 limit 条;分页由调用方控制)。
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

// 确认删除(回收配额;总数增减在同一事务内完成,无竞争)。
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
		var freed int64
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
		if freed > 0 {
			total := m.readTotalLocked(tx) - freed
			if total < 0 {
				total = 0
			}
			if err := m.writeTotalLocked(tx, total); err != nil {
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
