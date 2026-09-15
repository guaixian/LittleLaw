package main

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"strconv"
)

// 设备身份挑战:服务端发 nonce,设备用身份证书私钥对
// sha256("littlelaw-hello-v1|" + 长度前缀字段) 签名,服务端用证书公钥
// 验签并核对指纹。签名摘要做域分隔 + 长度前缀(签名协议卫生,
// 防跨协议/拼接歧义攻击)。服务器不存储任何私钥;
// deviceID→指纹 的首见绑定见 identity.go(Registry)。

func newNonce() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func authDigest(deviceID, fingerprint, nonce string) [32]byte {
	var b []byte
	b = append(b, "littlelaw-hello-v1|"...)
	for _, f := range []string{deviceID, fingerprint, nonce} {
		b = append(b, []byte(strconv.Itoa(len(f)))...)
		b = append(b, ':')
		b = append(b, f...)
	}
	return sha256.Sum256(b)
}

// 解析 PEM 证书并提取 ECDSA 公钥。
func pubKeyFromCertPEM(certPEM string) (*ecdsa.PublicKey, []byte, error) {
	block, _ := pem.Decode([]byte(certPEM))
	if block == nil {
		return nil, nil, errors.New("cert PEM decode failed")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, nil, fmt.Errorf("cert parse: %w", err)
	}
	pub, ok := cert.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return nil, nil, errors.New("cert public key is not ECDSA")
	}
	return pub, cert.Raw, nil
}

// 校验:签名合法 + 指纹匹配。
func verifyHello(deviceID, fingerprint, certPEM, sigHex, nonce string) error {
	if deviceID == "" || fingerprint == "" {
		return errors.New("missing deviceId or fingerprint")
	}
	pub, certRaw, err := pubKeyFromCertPEM(certPEM)
	if err != nil {
		return err
	}
	// 指纹 = 证书 DER 的 SHA-256 hex。
	fpr := sha256.Sum256(certRaw)
	if hex.EncodeToString(fpr[:]) != fingerprint {
		return errors.New("fingerprint mismatch with certificate")
	}
	sig, err := hex.DecodeString(sigHex)
	if err != nil || len(sig) != 64 {
		return errors.New("bad signature encoding (expect 64-byte r||s)")
	}
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	digest := authDigest(deviceID, fingerprint, nonce)
	if !ecdsa.Verify(pub, digest[:], r, s) {
		return errors.New("signature verify failed")
	}
	return nil
}
