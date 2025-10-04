# ビルドステージ
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Goモジュールのダウンロード
COPY go.mod go.sum ./
RUN go mod download

# ソースコードのコピーとビルド
COPY . .
RUN go build -o main .

# 本番ステージ
FROM alpine:latest

WORKDIR /app

# 証明書などのコピー（SSL/TLS通信に必要）
RUN apk --no-cache add ca-certificates

# ビルドしたバイナリとHTMLをコピー
COPY --from=builder /app/main .
COPY --from=builder /app/index.html .

EXPOSE 8080

CMD ["./main"]
