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
