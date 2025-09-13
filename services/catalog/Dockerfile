FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm i
COPY . .
EXPOSE 8002
CMD ["npm","start"]
