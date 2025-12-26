# 1️⃣ Dart image
FROM dart:stable AS build

# 2️⃣ Work directory
WORKDIR /app

# 3️⃣ Pubspec files
COPY pubspec.* ./
RUN dart pub get

# 4️⃣ Source code
COPY . .

# 5️⃣ Compile to executable (tezroq va stabil)
RUN dart compile exe lib/bin/knowix_bot.dart -o bot

# ===============================
# 6️⃣ Minimal runtime image
FROM debian:bullseye-slim

WORKDIR /app

# SSL uchun kerak
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Binary ko‘chiramiz
COPY --from=build /app/bot /app/bot

# Render uchun port (majburiy emas, lekin yaxshi amaliyot)
EXPOSE 8080

# 7️⃣ Start bot
CMD ["./bot"]
