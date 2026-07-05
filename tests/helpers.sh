# tests/helpers.sh — 공용 테스트 헬퍼 (source 해서 사용)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass_count=0
fail_count=0

ok()   { pass_count=$((pass_count+1)); echo "  ✓ $1"; }
fail() { fail_count=$((fail_count+1)); echo "  ✗ $1"; [[ -n "${2:-}" ]] && echo "    → $2"; }

assert_rc() { # <설명> <기대 rc> <실제 rc>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1" "기대 rc=$2, 실제 rc=$3"; fi
}
assert_contains() { # <설명> <포함되어야 할 문자열> <실제 출력>
  if printf '%s' "$3" | grep -qF "$2"; then ok "$1"; else fail "$1" "누락: '$2' / 출력: $(printf '%s' "$3" | head -3)"; fi
}
assert_not_contains() { # <설명> <없어야 할 문자열> <실제 출력>
  if printf '%s' "$3" | grep -qF "$2"; then fail "$1" "존재하면 안 됨: '$2'"; else ok "$1"; fi
}
assert_file()    { if [[ -f "$2" ]]; then ok "$1"; else fail "$1" "파일 없음: $2"; fi; }
assert_no_file() { if [[ -f "$2" ]]; then fail "$1" "파일이 있으면 안 됨: $2"; else ok "$1"; fi; }

summary() {
  echo
  echo "── $(basename "$0"): 통과 $pass_count, 실패 $fail_count"
  (( fail_count == 0 )) || exit 1
}

# 임시 git 프로젝트 + flywheel 씨앗 + 초기 커밋
make_fixture() { # <디렉터리>
  mkdir -p "$1"
  cd "$1"
  git -c init.defaultBranch=main init -q
  git config user.email "test@flywheel.local"
  git config user.name "flywheel-test"
  git config commit.gpgsign false
  "$REPO_ROOT/scripts/seed.sh" > /dev/null
  echo "hello" > src.txt
  git add -A
  git commit -qm "init: 픽스처"
}

# journal 갱신 헬퍼 (C1 통과용)
touch_journal() {
  echo "- $(date '+%T') 테스트 사이클 기록" >> ".flywheel/journal/$(date '+%F').md"
}
