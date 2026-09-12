# LittleLaw rendezvous 中转服务器
# 构建:  docker build -t littlelaw-rendezvous .
# 运行:  docker run -d -p 47600:47600 -v rendezvous-data:/data littlelaw-rendezvous
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/rendezvous .

FROM alpine:3.20
RUN adduser -D -u 10001 littlelaw
USER littlelaw
WORKDIR /data
COPY --from=build /out/rendezvous /usr/local/bin/rendezvous
EXPOSE 47600
# 数据(离线邮箱 bbolt)持久化到 /data
ENTRYPOINT ["rendezvous", "-addr", ":47600", "-db", "/data/rendezvous.db"]
