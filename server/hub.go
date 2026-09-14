package main

import (
	"sync"
)

// 在线注册表:deviceID → 连接;订阅关系:观察者 deviceID → 关注的 deviceID 集合。
type Hub struct {
	mu       sync.RWMutex
	online   map[string]*Client
	watchers map[string]map[string]bool // watcherID → {watchedID: true}
}

func NewHub() *Hub {
	return &Hub{
		online:   make(map[string]*Client),
		watchers: make(map[string]map[string]bool),
	}
}

func (h *Hub) isOnline(id string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.online[id]
	return ok
}

// 注册上线,并广播 peer_online 给关注者。
func (h *Hub) register(c *Client) {
	h.mu.Lock()
	// 同设备重复连接:踢掉旧连接(以新为准)。
	if old, ok := h.online[c.deviceID]; ok && old != c {
		old.kick()
	}
	h.online[c.deviceID] = c
	watchers := h.watchersOfLocked(c.deviceID)
	h.mu.Unlock()

	for _, w := range watchers {
		w.sendJSON(PeerEventFrame{Type: "peer_online", ID: c.deviceID, Endpoint: c.endpoint})
	}
}

// 下线,广播 peer_offline 给关注者。
func (h *Hub) unregister(c *Client) {
	h.mu.Lock()
	if cur, ok := h.online[c.deviceID]; !ok || cur != c {
		h.mu.Unlock()
		return
	}
	delete(h.online, c.deviceID)
	delete(h.watchers, c.deviceID)
	watchers := h.watchersOfLocked(c.deviceID)
	h.mu.Unlock()

	for _, w := range watchers {
		w.sendJSON(PeerEventFrame{Type: "peer_offline", ID: c.deviceID})
	}
}

// 设置关注集合,并回送当前快照。
func (h *Hub) subscribe(c *Client, ids []string) {
	h.mu.Lock()
	set := make(map[string]bool, len(ids))
	for _, id := range ids {
		if id != "" && id != c.deviceID {
			set[id] = true
		}
	}
	h.watchers[c.deviceID] = set
	h.mu.Unlock()

	// 快照。
	online := make([]PresenceItem, 0)
	offline := make([]string, 0)
	h.mu.RLock()
	for id := range set {
		if c, ok := h.online[id]; ok {
			online = append(online, PresenceItem{ID: id, Endpoint: c.endpoint})
		} else {
			offline = append(offline, id)
		}
	}
	h.mu.RUnlock()
	c.sendJSON(PresenceFrame{Type: "presence", Online: online, Offline: offline})
}

func (h *Hub) watchersOfLocked(watchedID string) []*Client {
	var out []*Client
	for watcherID, set := range h.watchers {
		if set[watchedID] {
			if c, ok := h.online[watcherID]; ok {
				out = append(out, c)
			}
		}
	}
	return out
}

// 定向转发(信令):仅当对端在线。
func (h *Hub) forwardTo(to string, frame SignalToClientFrame) bool {
	h.mu.RLock()
	c, ok := h.online[to]
	h.mu.RUnlock()
	if !ok {
		return false
	}
	return c.sendJSON(frame)
}

// 任意帧定向投递(邮箱直投等),仅当对端在线。
func (h *Hub) deliverJSON(to string, v any) bool {
	h.mu.RLock()
	c, ok := h.online[to]
	h.mu.RUnlock()
	if !ok {
		return false
	}
	return c.sendJSON(v)
}
