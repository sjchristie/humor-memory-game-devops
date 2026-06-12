# Verification

**Project:** Humor Memory Game  
**Phase:** Containerisation — Docker & Docker Compose  
**Document:** Verification  
**Previous:** [BUILD_AND_START.md](BUILD_AND_START.md)  
**Next:** [GIT_WORKFLOW.md](GIT_WORKFLOW.md)

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Section 1 — Infrastructure Tests](#2-section-1--infrastructure-tests)
3. [Section 2 — API Endpoint Tests](#3-section-2--api-endpoint-tests)
4. [Section 3 — End-to-End Game Flow Tests](#4-section-3--end-to-end-game-flow-tests)
5. [Section 4 — Persistence Tests](#5-section-4--persistence-tests)
6. [Create and Run the Automated Test Suite](#6-create-and-run-the-automated-test-suite)
7. [Verification Checkpoint](#7-verification-checkpoint)

---

## 1. Prerequisites

All four containers must be running and healthy before testing:

```bash
cd ~/workspace/humor-memory-game-devops
docker compose ps
```

Expected:

```
NAME                  IMAGE                               STATUS
humor-game-backend    humor-memory-game-backend:latest    Up (healthy)
humor-game-frontend   humor-memory-game-frontend:latest   Up (healthy)
humor-game-postgres   postgres:15.2-alpine                Up (healthy)
humor-game-redis      redis:7.0-alpine                    Up (healthy)
```

If any service is not healthy — check logs before proceeding:

```bash
docker compose logs <service-name>
```

---

## 2. Section 1 — Infrastructure Tests

### Test 1: Frontend Loads in Browser

Open a browser and navigate to:

```
http://192.168.30.11:3000
```

Expected:

- Page loads without errors
- Game interface visible with title "Humor Memory Game"
- Navigation tabs visible: Game, Leaderboard, My Stats, About
- Buttons respond when clicked
- No red errors in browser console (press F12 to open Dev Tools)

---

### Test 2: Frontend Serves HTML

```bash
curl http://localhost:3000 | head -20
```

Expected:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <title>🎮 Humor Memory Game - DevOps Learning Edition 😂</title>
```

---

### Test 3: Environment Variable Substitution

Confirms `${API_BASE_URL}` was replaced at container startup by `start.sh`:

```bash
docker exec -i humor-game-frontend grep "API_BASE_URL" /usr/share/nginx/html/index.html
```

Expected:

```
window.API_BASE_URL = '/api';
```

Not expected — substitution failed:

```
window.API_BASE_URL = '${API_BASE_URL}';
```

If the placeholder is still present, rebuild the frontend:

```bash
docker compose build --no-cache frontend
docker compose up -d frontend
```

---

### Test 4: Backend Health Check (Direct)

```bash
curl -s http://localhost:3001/api/health | python3 -m json.tool
```

Expected:

```json
{
    "status": "healthy",
    "timestamp": "2026-06-11T00:00:00.000Z",
    "services": {
        "database": "connected",
        "redis": "connected",
        "api": "running"
    },
    "version": "1.0.0",
    "environment": "development"
}
```

---

### Test 5: Backend Health Check via Nginx Proxy

Confirms Nginx is correctly proxying `/api/` requests to the backend:

```bash
curl -s http://localhost:3000/api/health | python3 -m json.tool
```

Expected — identical response to Test 4. If Test 4 passes but Test 5 fails, the Nginx proxy configuration has an issue.

---

### Test 6: Backend Health Check Status Code

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/api/health
```

Expected:

```
200
```

---

### Test 7: Database Tables

```bash
docker compose exec -i postgres psql -U gameuser -d humor_memory_game -c "\dt"
```

Expected:

```
          List of relations
 Schema |      Name       | Type  |  Owner
--------+-----------------+-------+----------
 public | daily_challenges| table | gameuser
 public | game_matches    | table | gameuser
 public | games           | table | gameuser
 public | users           | table | gameuser
(4 rows)
```

---

### Test 8: Redis Connection

```bash
docker exec -i humor-game-redis redis-cli -a gamepass123 ping
```

Expected:

```
PONG
```

```bash
docker exec -i humor-game-redis redis-cli -a gamepass123 SET test_key "test_value"
```

Expected:

```
OK
```

```bash
docker exec -i humor-game-redis redis-cli -a gamepass123 GET test_key
```

Expected:

```
"test_value"
```

---

### Test 9: Network Isolation Security Test

Verify the frontend **cannot** reach the database — this is the expected result and confirms network isolation is working:

```bash
docker compose exec -i frontend sh -c "wget -qO- http://postgres:5432 2>&1"
```

Expected — connection fails:

```
wget: bad address 'postgres'
```

Verify the backend **can** reach the database:

```bash
docker compose exec -i backend nc -zv postgres 5432
```

Expected — connection succeeds:

```
postgres (172.xx.xx.xx:5432) open
```

---

### Test 10: Container Resource Usage

```bash
docker stats --no-stream
```

Expected approximate values at idle:

```
CONTAINER             CPU %    MEM USAGE / LIMIT
humor-game-postgres   0.05%    45MiB / 7.5GiB
humor-game-redis      0.01%    2MiB / 7.5GiB
humor-game-backend    0.12%    78MiB / 7.5GiB
humor-game-frontend   0.02%    12MiB / 7.5GiB
```

All values should be under 5% CPU at idle.

---

### Test 11: Redis Data Persistence

```bash
# Write test data
docker exec -i -e REDISCLI_AUTH="gamepass123" humor-game-redis redis-cli SET persistence_test "data_survives_restart"


# Read it back
docker exec -i -e REDISCLI_AUTH="gamepass123" humor-game-redis redis-cli GET persistence_test

```

Expected:

```
"data_survives_restart"
```

```bash
# Restart Redis
docker compose restart redis
sleep 5

# Read again after restart — must still be present
docker exec -i -e REDISCLI_AUTH="gamepass123" humor-game-redis redis-cli GET persistence_test

```

Expected:

```
"data_survives_restart"
```

---

### Test 12: PostgreSQL Data Persistence

```bash
# Write a test record
docker compose exec -i postgres psql -U gameuser -d humor_memory_game \
  -c "INSERT INTO users (username) VALUES ('persistence_test_user');"

# Read it back
docker compose exec -i postgres psql -U gameuser -d humor_memory_game \
  -c "SELECT username FROM users WHERE username='persistence_test_user';"
```

Expected:

```
INSERT 0 1

        username
------------------------
 persistence_test_user
(1 row)
```

```bash
# Restart PostgreSQL
docker compose restart postgres
sleep 10

# Read again after restart — must still be present
docker compose exec -i postgres psql -U gameuser -d humor_memory_game \
  -c "SELECT username FROM users WHERE username='persistence_test_user';"
```

Expected — record still present:

```
        username
------------------------
 persistence_test_user
(1 row)
```

---

### Test 13: Log Integrity Check

Check all containers for silent errors:

```bash
docker compose logs --tail=50 backend | grep -i "error\|warn\|fail"
docker compose logs --tail=50 postgres | grep -i "error\|fail"
docker compose logs --tail=50 redis | grep -i "error\|fail"
```

Expected — no output, or only non-critical warnings.

**Redis memory overcommit warning:**

The following warning may appear in Redis logs — it is a known Linux VM kernel setting, not an application error:

```
WARNING Memory overcommit must be enabled! Without it, a background save or
replication may fail under low memory condition.
```

**Fix — apply immediately without reboot:**

```bash
sudo sysctl vm.overcommit_memory=1
```

**Fix — make permanent across reboots:**

```bash
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf
```

**Verify:**

```bash
cat /proc/sys/vm/overcommit_memory
# Expected: 1
```

**Restart Redis to confirm warning is gone:**

```bash
docker compose stop redis
docker compose rm -f redis
docker compose up -d redis
sleep 5
docker compose logs redis | grep -i "warning\|error"
# Expected: no output
```

---

## 3. Section 2 — API Endpoint Tests

### Test 14: API Root Endpoint

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/api
```

Expected:

```
200
```

---

### Test 15: Leaderboard Endpoint

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/api/leaderboard
```

Expected:

```
200
```

---

### Test 16: Fresh Leaderboard Endpoint

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/api/leaderboard/fresh
```

Expected:

```
200
```

---

### Test 17: Leaderboard Stats Endpoint

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/api/leaderboard/stats
```

Expected:

```
200
```

---

### Test 18: Daily Challenge Endpoint

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/api/game/daily-challenge
```

Expected:

```
200
```

---

## 4. Section 3 — End-to-End Game Flow Tests

These tests exercise the complete application flow from user creation through game completion.

### Test 19: Create User

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:3001/api/scores/user \
  -H "Content-Type: application/json" \
  -d '{"username": "testplayerverify"}'
```

Expected:

```
200
```

---

### Test 20: Start Game Session

```bash
curl -s -X POST http://localhost:3001/api/game/start \
  -H "Content-Type: application/json" \
  -d '{"username": "testplayerverify", "difficulty": "easy"}' | python3 -m json.tool
```

Expected — response includes a `gameId` and `cards` array.

---

### Test 21: Submit Card Match

> The game flow tests (Tests 21–22) require a live `gameId` and card IDs captured from Test 20. Manual substitution is error-prone. Use `game_check.sh` in Section 6 which handles all ID capture and substitution automatically.

---

### Test 22: Complete Game

> See note above — use `game_check.sh` in Section 6 for all game flow tests.

---

## 5. Section 4 — Persistence Tests

Covered in Tests 11 and 12 above — Redis and PostgreSQL data persistence across container restarts.

---

## 6. Create and Run the Automated Test Suite

The `game_check.sh` script runs all 25 tests automatically across all four sections. It handles game ID and card ID capture automatically — no manual intervention required.

### Create the Script

```bash
cat > ~/workspace/humor-memory-game-devops/game_check.sh << 'ENDOFSCRIPT'
#!/bin/sh
BASE="http://localhost:3001"
FRONTEND="http://localhost:3000"
USERNAME="testplayer$(date +%s)"
PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }
header() { echo ""; echo "========================================"; echo "  $1"; echo "========================================"; }
check_status() {
    LABEL=$1; EXPECTED=$2; ACTUAL=$3
    if [ "$ACTUAL" = "$EXPECTED" ]; then pass "$LABEL (HTTP $ACTUAL)"
    else fail "$LABEL (Expected HTTP $EXPECTED, got HTTP $ACTUAL)"; fi
}

header "Section 1: Infrastructure"

echo "[ Test 1 ] Backend health check"
RESPONSE=$(curl -s $BASE/api/health)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/health)
check_status "Backend responding" "200" "$STATUS"
echo "$RESPONSE" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    db=d.get('services',{}).get('database','unknown')
    redis=d.get('services',{}).get('redis','unknown')
    print(f'     Database: {db}')
    print(f'     Redis:    {redis}')
except: pass
" 2>/dev/null

echo "[ Test 2 ] Frontend serving HTML"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $FRONTEND)
check_status "Frontend responding on port 3000" "200" "$STATUS"

echo "[ Test 3 ] Nginx proxy"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $FRONTEND/api/health)
check_status "Nginx proxying /api/ to backend" "200" "$STATUS"

echo "[ Test 4 ] Environment variable substitution"
PLACEHOLDER=$(docker exec -i humor-game-frontend grep "API_BASE_URL" /usr/share/nginx/html/index.html | grep '\${API_BASE_URL}' | wc -l)
if [ "$PLACEHOLDER" = "0" ]; then pass "API_BASE_URL substituted in index.html"
else fail "API_BASE_URL placeholder still present in index.html"; fi

echo "[ Test 5 ] Container status"
for SERVICE in backend frontend postgres redis; do
    STATUS=$(docker compose ps $SERVICE --format "{{.Status}}" 2>/dev/null | head -1)
    if echo "$STATUS" | grep -qi "up"; then pass "Container humor-game-$SERVICE is running"
    else fail "Container humor-game-$SERVICE is NOT running (status: $STATUS)"; fi
done

echo "[ Test 6 ] Redis connection"
PONG=$(docker exec -i humor-game-redis redis-cli -a gamepass123 ping 2>/dev/null)
if echo "$PONG" | grep -q "PONG"; then pass "Redis ping responded with PONG"
else fail "Redis ping failed (got: $PONG)"; fi

echo "[ Test 7 ] PostgreSQL schema"
TABLES=$(docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game -c "\dt" 2>/dev/null | grep "table" | wc -l)
if [ "$TABLES" -gt "0" ]; then pass "PostgreSQL tables found ($TABLES tables)"
else fail "No PostgreSQL tables found — schema may not have initialised"; fi

echo "[ Test 8 ] Network isolation"
RESULT=$(docker compose exec -i frontend sh -c "wget -qO- http://postgres:5432 2>&1" 2>&1)
if echo "$RESULT" | grep -qi "refused\|failed\|unknown\|not found\|timed out\|connect\|bad address"; then
    pass "Frontend cannot reach postgres (network isolation working)"
else fail "Frontend CAN reach postgres (network isolation broken)"; fi

header "Section 2: API Endpoints"

echo "[ Test 9 ] API root endpoint"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api)
check_status "GET /api returns endpoint list" "200" "$STATUS"

echo "[ Test 10 ] Leaderboard"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/leaderboard)
check_status "GET /api/leaderboard" "200" "$STATUS"

echo "[ Test 11 ] Fresh leaderboard"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/leaderboard/fresh)
check_status "GET /api/leaderboard/fresh" "200" "$STATUS"

echo "[ Test 12 ] Leaderboard stats"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/leaderboard/stats)
check_status "GET /api/leaderboard/stats" "200" "$STATUS"

echo "[ Test 13 ] Daily challenge"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/game/daily-challenge)
check_status "GET /api/game/daily-challenge" "200" "$STATUS"

header "Section 3: End-to-End Game Flow"

echo "  Using username: $USERNAME"
echo ""

echo "[ Test 14 ] Create user"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/scores/user \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"$USERNAME\"}")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then pass "POST /api/scores/user (HTTP $STATUS)"
else fail "POST /api/scores/user (HTTP $STATUS)"; fi

echo "[ Test 15 ] Start game session"
RESPONSE=$(curl -s -X POST $BASE/api/game/start \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"$USERNAME\", \"difficulty\": \"easy\"}")
GAME_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['game']['gameId'])" 2>/dev/null)
if [ -n "$GAME_ID" ]; then pass "POST /api/game/start — gameId: $GAME_ID"
else fail "POST /api/game/start — could not extract gameId"; echo "  Response was: $RESPONSE"; fi

PAIR=$(echo "$RESPONSE" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    cards=d['game']['cards']
    names={}
    for card in cards:
        n=card['name']
        if n not in names:
            names[n]=[]
        names[n].append(card['id'])
    for n,ids in names.items():
        if len(ids)==2:
            print(ids[0] + ' ' + ids[1])
            break
except Exception as e:
    print('')
" 2>/dev/null)
CARD1=$(echo "$PAIR" | cut -d' ' -f1)
CARD2=$(echo "$PAIR" | cut -d' ' -f2)
if [ -n "$CARD1" ] && [ -n "$CARD2" ]; then echo "     Cards to match: $CARD1 and $CARD2"
else fail "Could not extract card IDs from game response"; fi

echo "[ Test 16 ] Submit card match"
if [ -n "$GAME_ID" ] && [ -n "$CARD1" ] && [ -n "$CARD2" ]; then
    MATCH_RESPONSE=$(curl -s -X POST $BASE/api/game/match \
        -H "Content-Type: application/json" \
        -d "{\"gameId\": \"$GAME_ID\", \"card1Id\": \"$CARD1\", \"card2Id\": \"$CARD2\", \"matchTime\": 3000}")
    SUCCESS=$(echo "$MATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success','false'))" 2>/dev/null)
    if [ "$SUCCESS" = "True" ] || [ "$SUCCESS" = "true" ]; then pass "POST /api/game/match — match accepted"
    else fail "POST /api/game/match — match rejected"; echo "     Response: $MATCH_RESPONSE"; fi
else fail "POST /api/game/match — skipped (missing gameId or card IDs)"; fi

echo "[ Test 17 ] Complete game"
if [ -n "$GAME_ID" ]; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/api/game/complete \
        -H "Content-Type: application/json" \
        -d "{\"gameId\": \"$GAME_ID\", \"username\": \"$USERNAME\", \"timeElapsed\": 120000, \"finalScore\": 180}")
    check_status "POST /api/game/complete" "200" "$STATUS"
else fail "POST /api/game/complete — skipped (no gameId)"; fi

echo "[ Test 18 ] Retrieve game details"
if [ -n "$GAME_ID" ]; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/api/game/$GAME_ID)
    check_status "GET /api/game/:gameId" "200" "$STATUS"
else fail "GET /api/game/:gameId — skipped (no gameId)"; fi

echo "[ Test 19 ] User scores"
SCORE_RESPONSE=$(curl -s $BASE/api/scores/$USERNAME)
BEST_SCORE=$(echo "$SCORE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['bestScore'])" 2>/dev/null)
TOTAL_GAMES=$(echo "$SCORE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['totalGames'])" 2>/dev/null)
if [ -n "$BEST_SCORE" ]; then pass "GET /api/scores/:username — bestScore: $BEST_SCORE, totalGames: $TOTAL_GAMES"
else fail "GET /api/scores/:username — could not retrieve scores"; fi

echo "[ Test 20 ] User leaderboard rank"
RANK=$(echo "$SCORE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['statistics']['globalRank'])" 2>/dev/null)
if [ -n "$RANK" ]; then pass "Global rank retrieved — rank: $RANK"
else fail "Could not retrieve global rank"; fi

header "Section 4: Persistence"

echo "[ Test 21 ] Redis data persistence"
docker exec -i humor-game-redis redis-cli -a gamepass123 SET persist_test "survives_restart" > /dev/null 2>&1
docker compose restart redis > /dev/null 2>&1
sleep 5
RESULT=$(docker exec -i humor-game-redis redis-cli -a gamepass123 GET persist_test 2>/dev/null)
if echo "$RESULT" | grep -q "survives_restart"; then pass "Redis data survived container restart"
else fail "Redis data lost after container restart (got: $RESULT)"; fi

echo "[ Test 22 ] PostgreSQL data persistence"
docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game \
    -c "INSERT INTO users (username) VALUES ('persist_test_$(date +%s)') ON CONFLICT DO NOTHING;" > /dev/null 2>&1
COUNT_BEFORE=$(docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ')
docker compose restart postgres > /dev/null 2>&1
sleep 10
COUNT_AFTER=$(docker exec -i humor-game-postgres psql -U gameuser -d humor_memory_game -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ')
if [ "$COUNT_BEFORE" = "$COUNT_AFTER" ] && [ -n "$COUNT_BEFORE" ]; then
    pass "PostgreSQL data survived container restart ($COUNT_AFTER rows)"
else fail "PostgreSQL row count changed after restart (before: $COUNT_BEFORE, after: $COUNT_AFTER)"; fi

header "Test Summary"
TOTAL=$((PASS + FAIL))
echo "  Total tests: $TOTAL"
echo "  Passed:      $PASS"
echo "  Failed:      $FAIL"
echo ""
if [ "$FAIL" = "0" ]; then echo "  ✅ ALL TESTS PASSED — application fully verified"
else echo "  ❌ $FAIL TEST(S) FAILED — review output above"; fi
echo ""
echo "  Game ID used: $GAME_ID"
echo "  Username used: $USERNAME"
echo "========================================"
ENDOFSCRIPT
chmod +x ~/workspace/humor-memory-game-devops/game_check.sh
EOF
```

Make the script executable and run it:

```bash
chmod +x ~/workspace/humor-memory-game-devops/game_check.sh

cd ~/workspace/humor-memory-game-devops

sh game_check.sh
```

### Expected Output — All 25 Tests Passing

```
========================================
  Section 1: Infrastructure
========================================
[ Test 1 ] Backend health check
  ✅ PASS: Backend responding (HTTP 200)
     Database: connected
     Redis:    connected
[ Test 2 ] Frontend serving HTML
  ✅ PASS: Frontend responding on port 3000 (HTTP 200)
[ Test 3 ] Nginx proxy
  ✅ PASS: Nginx proxying /api/ to backend (HTTP 200)
[ Test 4 ] Environment variable substitution
  ✅ PASS: API_BASE_URL substituted in index.html
[ Test 5 ] Container status
  ✅ PASS: Container humor-game-backend is running
  ✅ PASS: Container humor-game-frontend is running
  ✅ PASS: Container humor-game-postgres is running
  ✅ PASS: Container humor-game-redis is running
[ Test 6 ] Redis connection
  ✅ PASS: Redis ping responded with PONG
[ Test 7 ] PostgreSQL schema
  ✅ PASS: PostgreSQL tables found (4 tables)
[ Test 8 ] Network isolation
  ✅ PASS: Frontend cannot reach postgres (network isolation working)

========================================
  Section 2: API Endpoints
========================================
[ Test 9 ] API root endpoint
  ✅ PASS: GET /api returns endpoint list (HTTP 200)
[ Test 10 ] Leaderboard
  ✅ PASS: GET /api/leaderboard (HTTP 200)
[ Test 11 ] Fresh leaderboard
  ✅ PASS: GET /api/leaderboard/fresh (HTTP 200)
[ Test 12 ] Leaderboard stats
  ✅ PASS: GET /api/leaderboard/stats (HTTP 200)
[ Test 13 ] Daily challenge
  ✅ PASS: GET /api/game/daily-challenge (HTTP 200)

========================================
  Section 3: End-to-End Game Flow
========================================
  Using username: testplayer1780447228

[ Test 14 ] Create user
  ✅ PASS: POST /api/scores/user (HTTP 200)
[ Test 15 ] Start game session
  ✅ PASS: POST /api/game/start — gameId: 1d0536a4-fe05-4716-8469-5e63b12499c6
     Cards to match: lightning_1 and lightning_2
[ Test 16 ] Submit card match
  ✅ PASS: POST /api/game/match — match accepted
[ Test 17 ] Complete game
  ✅ PASS: POST /api/game/complete (HTTP 200)
[ Test 18 ] Retrieve game details
  ✅ PASS: GET /api/game/:gameId (HTTP 200)
[ Test 19 ] User scores
  ✅ PASS: GET /api/scores/:username — bestScore: 193, totalGames: 1
[ Test 20 ] User leaderboard rank
  ✅ PASS: Global rank retrieved — rank: 42

========================================
  Section 4: Persistence
========================================
[ Test 21 ] Redis data persistence
  ✅ PASS: Redis data survived container restart
[ Test 22 ] PostgreSQL data persistence
  ✅ PASS: PostgreSQL data survived container restart (16 rows)

========================================
  Test Summary
========================================
  Total tests: 25
  Passed:      25
  Failed:      0

  ✅ ALL TESTS PASSED — application fully verified

  Game ID used: 1d0536a4-fe05-4716-8469-5e63b12499c6
  Username used: testplayer1780447228
========================================
```

---

## 7. Verification Checkpoint

```bash
cd ~/workspace/humor-memory-game-devops

# All four services healthy
docker compose ps
# Expected: all four containers Up (healthy)

# Automated test suite passes
sh game_check.sh
# Expected: Total tests: 25 / Passed: 25 / Failed: 0

# Frontend accessible
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Expected: 200

# Backend API accessible
curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/health
# Expected: 200

# Nginx proxy working
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health
# Expected: 200
```

All 25 tests passing? Proceed to the git workflow to commit and push the completed repository.

---

**Next → [GIT_WORKFLOW.md](GIT_WORKFLOW.md)**
