import os, json, smtplib, requests, redis, pika
from email.mime.text import MIMEText

AMQP_URL = os.getenv("AMQP_URL","amqp://guest:guest@rabbitmq:5672/")
PAY_URL = os.getenv("PAYMENTS_URL","http://payments:8004")
SMTP_HOST = os.getenv("SMTP_HOST","mailhog")
SMTP_PORT = int(os.getenv("SMTP_PORT","1025"))
REDIS_URL = os.getenv("REDIS_URL","redis://redis:6379/0")

r = redis.Redis.from_url(REDIS_URL)

def send_email(to, subject, body):
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = 'noreply@megashop.local'
    msg['To'] = to
    s = smtplib.SMTP(SMTP_HOST, SMTP_PORT)
    s.sendmail(msg['From'], [to], msg.as_string())
    s.quit()

def handle_order(order):
    try:
        resp = requests.post(f"{PAY_URL}/charge", json={"order_id": order['order_id'], "amount": 100})
        data = resp.json()
        result = data.get('status','failed')
    except Exception:
        result = 'failed'
    r.setex(f"order:{order['order_id']}:payment", 300, result)
    send_email(order['user_email'], "Your MegaShop order", f"Order {order['order_id']} payment {result}!")
    print(f"[worker] processed order {order['order_id']} => {result}")

def main():
    params = pika.URLParameters(AMQP_URL)
    conn = pika.BlockingConnection(params)
    ch = conn.channel()
    ch.queue_declare(queue='orders', durable=False)
    def cb(ch_in, method, props, body):
        order = json.loads(body.decode())
        handle_order(order)
        ch_in.basic_ack(delivery_tag=method.delivery_tag)
    ch.basic_consume('orders', cb, auto_ack=False)
    print("[worker] waiting for messages...")
    ch.start_consuming()

if __name__ == "__main__":
    main()
