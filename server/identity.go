package main

import (
	"errors"

	"go.etcd.io/bbolt"
)

// 设备身份注册表(TOFU 的"F"):deviceID → 证书指纹 首见登记。
//
// 旧版身份完全自声明:verifyHello 只证明"签名者持有客户端带来的证书
// 私钥",deviceId 是随机 UUID 与证书无绑定——任意恶意客户端可以声明
// 受害者 deviceID,踢线、读删信箱、覆盖推送令牌、劫持信令。
// 现在同一 deviceID 只能对应首次登记的指纹;不一致直接拒绝。
var regBucket = []byte("identities")

var ErrIdentityConflict = errors.New("deviceId already bound to a different fingerprint")

type Registry struct {
	db *bbolt.DB
}

func NewRegistry(db *bbolt.DB) *Registry {
	return &Registry{db: db}
}

// Register 首见登记;已登记且指纹一致 → 幂等通过;不一致 → 冲突。
func (r *Registry) Register(deviceID, fingerprint string) error {
	return r.db.Update(func(tx *bbolt.Tx) error {
		root, err := tx.CreateBucketIfNotExists(regBucket)
		if err != nil {
			return err
		}
		if existing := root.Get([]byte(deviceID)); existing != nil {
			if string(existing) != fingerprint {
				return ErrIdentityConflict
			}
			return nil
		}
		return root.Put([]byte(deviceID), []byte(fingerprint))
	})
}

// Bound 返回已登记的指纹(无登记返回空)。
func (r *Registry) Bound(deviceID string) (string, error) {
	var fpr string
	err := r.db.View(func(tx *bbolt.Tx) error {
		root := tx.Bucket(regBucket)
		if root == nil {
			return nil
		}
		if v := root.Get([]byte(deviceID)); v != nil {
			fpr = string(v)
		}
		return nil
	})
	return fpr, err
}
