package main

import (
	"sync"
)

// 在线注册表:deviceID → 连接;订阅关系:观察者 deviceID → 关注的 deviceID 集合。
// watchedBy 反向索引:被关注 deviceID → 关注者集合(上线/下线广播 O(1)
// 定位关注者;旧版每次全表扫描且持写锁,4096 连接 × 512 订阅时单次
// ~2M 查找,连接抖动可让 presence 全局停摆)。
type Hub struct {
	mu        sync.RWMutex
	online    map[string]*Client
	watchers  map[string]map[string]bool // watcherID → {watchedID: true}
	watchedBy map[string]map[string]bool // watchedID → {watcherID: true}
}

func NewHub() *Hub {
	return &Hub{
		online:    make(map[string]*Client),
		watchers:  make(map[string]map[string]bool),
		watchedBy: make(map[string]map[string]bool),
	}
}

func (h *Hub) isOnline(id string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.online[id]
	return ok
}

// 注册上线,并广播 peer_online 给关注者。
// endpoint(对端家庭公网 IP:port)只披露给【双向关注】的观察者——
// 真实配对设备互相订阅;单向订阅者(陌生人/探测者)只看到在线状态。
func (h *Hub) register(c *Client) {
	h.mu.Lock()
	// 同设备重复连接:踢掉旧连接(以新为准)。
	if old, ok := h.online[c.deviceID]; ok && old != c {
		old.kick()
	}
	h.online[c.deviceID] = c
	watchers := h.watchersOfLocked(c.deviceID)
	mutual := h.mutualWatchersLocked(c.deviceID)
	h.mu.Unlock()

	for _, w := range watchers {
		endpoint := ""
		if mutual[w.deviceID] {
			endpoint = c.endpoint
		}
		w.sendJSON(PeerEventFrame{Type: "peer_online", ID: c.deviceID, Endpoint: endpoint})
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
	h.setWatchLocked(c.deviceID, nil)
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
	h.setWatchLocked(c.deviceID, set)

	online := make([]PresenceItem, 0)
	offline := make([]string, 0)
	for id := range set {
		if oc, ok := h.online[id]; ok {
			item := PresenceItem{ID: id}
			// endpoint 仅双向关注可见(隐私:家庭 IP 不向陌生订阅者披露)。
			if set2, ok := h.watchers[id]; ok && set2[c.deviceID] {
				item.Endpoint = oc.endpoint
			}
			online = append(online, item)
		} else {
			offline = append(offline, id)
		}
	}
	h.mu.Unlock()

	c.sendJSON(PresenceFrame{Type: "presence", Online: online, Offline: offline})
}

// setWatchLocked 全量替换某观察者的关注集合,同步维护反向索引。
func (h *Hub) setWatchLocked(watcherID string, set map[string]bool) {
	old := h.watchers[watcherID]
	for id := range old {
		if m := h.watchedBy[id]; m != nil {
			delete(m, watcherID)
			if len(m) == 0 {
				delete(h.watchedBy, id)
			}
		}
	}
	if set == nil {
		delete(h.watchers, watcherID)
		return
	}
	h.watchers[watcherID] = set
	for id := range set {
		if h.watchedBy[id] == nil {
			h.watchedBy[id] = make(map[string]bool)
		}
		h.watchedBy[id][watcherID] = true
	}
}

// watchersOfLocked 反向索引 O(1) 取关注者。
func (h *Hub) watchersOfLocked(watchedID string) []*Client {
	var out []*Client
	for watcherID := range h.watchedBy[watchedID] {
		if c, ok := h.online[watcherID]; ok {
			out = append(out, c)
		}
	}
	return out
}

// mutualWatchersLocked 双向关注(互相订阅 = 配对关系)的在线观察者集合。
func (h *Hub) mutualWatchersLocked(id string) map[string]bool {
	out := make(map[string]bool)
	for watcherID := range h.watchedBy[id] {
		if h.watchers[watcherID][id] {
			out[watcherID] = true
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
