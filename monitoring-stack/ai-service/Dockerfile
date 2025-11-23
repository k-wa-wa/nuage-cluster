FROM python:3.12

RUN apt update && apt install -y vim

# 作業ディレクトリを設定
WORKDIR /app

# 必要なパッケージをインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src ./src

# 5053ポートを公開
EXPOSE 5053

# サーバーを起動
CMD ["python", "src/agent/mcp_client.py"]
