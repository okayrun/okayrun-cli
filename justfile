default:
	@just --list

# Build the OKAY RUN CLI binary
build:
	go build -o bin/okay .

# Run all unit tests for the CLI with clean output control
test:
	#!/usr/bin/env bash
	set -euo pipefail
	mkdir -p logs
	TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
	FULL_LOG="logs/tests_${TIMESTAMP}_full.log"
	FAILED_LOG="logs/tests_${TIMESTAMP}_failed.log"
	
	echo "Running CLI tests..."
	set +e
	go test -v ./... > "${FULL_LOG}" 2>&1
	TEST_STATUS=$?
	set -e
	
	if [ $TEST_STATUS -eq 0 ]; then
		echo "All tests passed successfully!"
		echo "Log generated:"
		echo "  - Full Log: ${FULL_LOG}"
	else
		# Extract failed tests and details to the failure log
		awk '
		BEGIN { state = "idle"; buf = "" }
		/^=== RUN|^=== CONT/ {
			state = "buffering"
			buf = $0
			next
		}
		/^--- FAIL:/ {
			if (state == "buffering") {
				print buf
				print $0
			} else {
				print $0
			}
			state = "idle"
			buf = ""
			next
		}
		/^--- PASS:/ {
			state = "idle"
			buf = ""
			next
		}
		/^FAIL/ {
			print $0
			state = "idle"
			buf = ""
			next
		}
		{
			if (state == "buffering") {
				buf = buf "\n" $0
			}
		}
		' "${FULL_LOG}" > "${FAILED_LOG}"
		
		echo "ERROR: Some tests failed."
		echo "Two logs have been created:"
		echo "  - Full Log: ${FULL_LOG}"
		echo "  - Failures-only Log: ${FAILED_LOG}"
		echo ""
		echo "Failed Tests Summary:"
		echo "====================="
		cat "${FAILED_LOG}" || true
		echo "====================="
		exit $TEST_STATUS
	fi

# Stage, commit, push, PR, and merge changes in one go (handles repos with PR-only rulesets)
pr-land message branch_name="":
	#!/usr/bin/env bash
	set -euo pipefail
	command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI is required."; exit 1; }
	BRANCH="{{branch_name}}"
	if [[ -z "$BRANCH" ]]; then
	  SLUG=$(echo "{{message}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-|-$//g' | cut -c1-30)
	  BRANCH="auto-$SLUG"
	fi
	CURRENT_BRANCH=$(git branch --show-current)
	if [[ "$CURRENT_BRANCH" == "main" ]]; then
	  echo "Creating and switching to branch: $BRANCH"
	  git checkout -b "$BRANCH"
	else
	  echo "Using current branch: $CURRENT_BRANCH"
	  BRANCH="$CURRENT_BRANCH"
	fi
	echo "Staging and committing..."
	git add .
	git commit -m "{{message}}" || echo "No changes to commit."
	echo "Pushing branch $BRANCH..."
	git push -u origin "$BRANCH"
	echo "Creating Pull Request..."
	PR_URL=$(gh pr create --title "{{message}}" --body "Automated land via 'just pr-land'.")
	echo "PR Created: $PR_URL"
	echo "Merging Pull Request..."
	gh pr merge --merge --delete-branch
	echo "Syncing main..."
	git checkout main
	git pull origin main
	echo "Successfully landed changes!"
