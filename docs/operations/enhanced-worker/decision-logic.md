### Risk Assessment Matrix

| Risk Level | Criteria | Auto-Merge Policy |
|------------|----------|-------------------|
| **CRITICAL** | Security failures | ❌ Never auto-merge |
| **HIGH** | Critical files + failures, Complexity 4 + failures | ❌ Never auto-merge |
| **MEDIUM** | Complexity 3, Multiple failures | ✅ All 3 agents must pass |
| **LOW** | Simple changes | ✅ 2/3 agents must pass |

### Enhanced Safety Checks

1. **Test Coverage Enforcement**: Blocks auto-merge if production code changes without test modifications
2. **Critical File Protection**: Extra scrutiny for system-critical files (main.go, config files, etc.)
3. **Progressive Strictness**: Higher complexity = stricter requirements
4. **Security Priority**: Security failures always prevent auto-merge

### Decision Flow

```
PR Diff Analysis
    ↓
Extract: Functions, Files, Languages
    ↓
Calculate Complexity Score (1-4)
    ↓
Run AI Agents in Parallel
    ↓
Assess Risk Level
    ↓
Apply Decision Logic
    ↓
MERGE or REQUEST_REVIEW
```

### Complexity Scoring Algorithm

**Base Score Calculation**:
- Lines changed: +1 per line
- Files modified: +5 per file  
- Functions modified: +10 per function

**Complexity Levels**:
- **Level 1 (Low)**: Score < 50
- **Level 2 (Medium)**: Score 50-149
- **Level 3 (High)**: Score 150-299
- **Level 4 (Very High)**: Score ≥ 300

### Critical File Detection

Files automatically flagged as critical:
- `main.go`, `main.py`, `index.js`
- Configuration files (`config.*`, `.env`, `docker-compose.*`)
- Build files (`Makefile`, `Dockerfile`, `package.json`)
- Infrastructure files (`systemd/*`, `scripts/*`)

### Test File Detection

Patterns for test file identification:
- `*_test.go` (Go tests)
- `*.test.js`, `*.spec.js` (JavaScript/TypeScript tests)
- `test_*.py` (Python tests)
- `/test/`, `/tests/`, `__test__` directories
