package main

import (
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// 防滥用限制器:公共部署的最低防线。
//  - 每 IP 建连令牌桶(防扫描/重连风暴);
//  - 全局并发连接上限;
//  - 每客户端消息滑动窗口(防信令/邮箱刷屏)。
type Limiter struct {
	mu sync.Mutex

	// 每 IP 令牌桶。
	buckets map[string]*ipBucket

	burstPerMin int // 每 IP 每分钟新建连接数
	maxConns    int // 全局并发连接上限
	conns       int

	// 每客户端消息窗口。
	msgWindow time.Duration
	msgBurst  int
}

type ipBucket struct {
	tokens    float64
	lastAddMs int64
	lastUsed  int64 // 清理很久不活跃的桶
}

func NewLimiter(maxConns, burstPerMin, msgBurst int) *Limiter {
	return &Limiter{
		buckets:    make(map[string]*ipBucket),
		burstPerMin: burstPerMin,
		maxConns:   maxConns,
		msgWindow:  10 * time.Second,
		msgBurst:   msgBurst,
	}
}

func ipOf(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// 建连准入:IP 令牌桶 + 全局并发上限。
func (l *Limiter) AllowConn(r *http.Request) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.conns >= l.maxConns {
		return false
	}
	now := time.Now().UnixMilli()
	ip := ipOf(r)
	b, ok := l.buckets[ip]
	if !ok {
		// 顺手清理 1 小时未用的桶,防内存膨胀。
		if len(l.buckets) > 65536 {
			for k, v := range l.buckets {
				if now-v.lastUsed > int64(time.Hour/time.Millisecond) {
					delete(l.buckets, k)
				}
			}
		}
		b = &ipBucket{tokens: float64(l.burstPerMin), lastAddMs: now, lastUsed: now}
		l.buckets[ip] = b
	}
	// 补充速率:burstPerMin/分钟。
	elapsed := float64(now-b.lastAddMs) / 60000.0
	if elapsed > 0 {
		b.tokens += elapsed * float64(l.burstPerMin)
		if b.tokens > float64(l.burstPerMin) {
			b.tokens = float64(l.burstPerMin)
		}
		b.lastAddMs = now
	}
	b.lastUsed = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	l.conns++
	return true
}

func (l *Limiter) ConnClosed() {
	l.mu.Lock()
	l.conns--
	l.mu.Unlock()
}

// ---- 每客户端滑动窗口 ----

type msgWindow struct {
	mu     sync.Mutex
	stamps []int64
}

func (w *msgWindow) allow(window time.Duration, burst int) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	now := time.Now().UnixNano()
	cutoff := now - int64(window)
	// stamps 按时间递增,弹出过期头部。
	i := 0
	for ; i < len(w.stamps) && w.stamps[i] < cutoff; i++ {
	}
	w.stamps = w.stamps[i:]
	if len(w.stamps) >= burst {
		return false
	}
	w.stamps = append(w.stamps, now)
	return true
}

func writeTooMany(w http.ResponseWriter) {
	w.Header().Set("Retry-After", strconv.Itoa(10))
	w.WriteHeader(http.StatusTooManyRequests)
	_, _ = w.Write([]byte("too many connections"))
}
