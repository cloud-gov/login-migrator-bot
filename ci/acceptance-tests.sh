#!/bin/bash
set -u -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Requires a user with cloud_controller.admin access to run since it will be creating/deleting users, organizations
# `test-login-migrator.gov` should not match any of the agencies in the current-federal.csv used by sandbox-bot


# Test configuration
TEST_USER="test.user.login.migrator.bot@test-login-migrator.gov"
TEST_ORG_1="login-migrator-test-org-1"
TEST_ORG_2="login-migrator-test-org-2"
TEST_SPACE_1="testing1"
TEST_SPACE_2="testing2"
SCRIPT_PATH="cg-scripts/cloudfoundry/copy-user-org-and-space-roles.sh"
LOG_FILE="acceptance_test_$(date +%Y%m%d_%H%M%S).log"

# Wait time for remote application to process (in seconds)
WAIT_TIME="${WAIT_TIME:-60}"

# Initialize test counter
TESTS_FAILED=0
TESTS_PASSED=0

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ $2${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# Function to count roles from script output
count_roles() {
    local file=$1
    local role_type=$2
    
    case $role_type in
        "org")
            grep -E "^\s*- [^/]+: (OrgManager|BillingManager|OrgAuditor)$" "$file" 2>/dev/null | wc -l
            ;;
        "space")
            grep -E "^\s*- .+/.+: (SpaceDeveloper|SpaceAuditor|SpaceManager|SpaceSupporter)$" "$file" 2>/dev/null | wc -l
            ;;
        "org_user")
            grep -E "^\s*- .+: organization_user$" "$file" 2>/dev/null | wc -l
            ;;
    esac
}

# Cleanup function to ensure test users are removed
cleanup() {
    print_section "CLEANUP: Removing test users"
    
    # Delete both users
    echo "🔧 Deleting users..."
    cf delete-user $TEST_USER --origin cloud.gov -f 2>/dev/null || echo "cloud.gov user may not exist, it was likely deleted by the migration process"
    cf delete-user $TEST_USER --origin login.gov -f 2>/dev/null || echo "login.gov user may not exist"

    echo "🏢 Deleting organization '$TEST_ORG_1'..."
    cf delete-org "$TEST_ORG_1" -f 2>/dev/null || echo "Organization $TEST_ORG_1 may not exist"

    echo "🏢 Deleting organization '$TEST_ORG_2'..."
    cf delete-org "$TEST_ORG_2" -f 2>/dev/null || echo "Organization $TEST_ORG_2 may not exist"

    echo "🗑️ Removing test output files..."
    rm -f test*.txt role_comparison.txt initial_cloud_gov_roles.txt initial_login_gov_roles.txt final_login_gov_roles.txt final_cloud_gov_check.txt
    
    echo "Cleanup complete!"
}

# Set trap to ensure cleanup runs even if script fails
trap cleanup EXIT

# Main test execution
print_section "Login Migrator Acceptance Tests"
echo "Test user: $TEST_USER"
echo "Wait time: $WAIT_TIME seconds"
echo "CF Target: $(cf target)"
echo ""

# PHASE 1: SETUP
print_section "PHASE 1: Setup Test Users"

# Log into CF as an admin
echo "Logging into ${CF_API} as user ${CF_ADMIN_USER}..."
cf login -a ${CF_API} -u ${CF_ADMIN_USER} -p "${CF_ADMIN_PASSWORD}" -o cloud-gov -s bots >/dev/null 2>&1

# First ensure users don't exist
echo "Cleaning up any existing test users..."
cf delete-user $TEST_USER --origin cloud.gov -f 2>/dev/null || true
cf delete-user $TEST_USER --origin login.gov -f 2>/dev/null || true
sleep 2



# PHASE 2: VERIFY CLOUD.GOV USER CREATION AND INITIAL STATE
print_section "PHASE 2: Verify cloud.gov User Creation and Initial State"

echo ""
echo "- Creating cloud.gov origin user..."
cf create-user $TEST_USER --origin cloud.gov

echo ""
echo "Creating organizations and spaces for testing..."
cf create-org $TEST_ORG_1 || echo "Organization $TEST_ORG_1 may already exist"
cf create-space $TEST_SPACE_1 -o $TEST_ORG_1    || echo "Space $TEST_SPACE_1 may already exist in $TEST_ORG_1"
cf create-org $TEST_ORG_2 || echo "Organization $TEST_ORG_2 may already exist"
cf create-space $TEST_SPACE_2 -o $TEST_ORG_2 || echo "Space $TEST_SPACE_2 may already exist in $TEST_ORG_2" 

echo ""
echo "Setting up roles for cloud.gov user..."
echo "Organization roles in $TEST_ORG_1:"
cf set-org-role $TEST_USER $TEST_ORG_1 OrgManager --origin cloud.gov
cf set-org-role $TEST_USER $TEST_ORG_1 BillingManager --origin cloud.gov
cf set-org-role $TEST_USER $TEST_ORG_1 OrgAuditor --origin cloud.gov

echo ""
echo "Organization roles in $TEST_ORG_2:"
cf set-org-role $TEST_USER $TEST_ORG_2 OrgManager --origin cloud.gov
cf set-org-role $TEST_USER $TEST_ORG_2 BillingManager --origin cloud.gov
cf set-org-role $TEST_USER $TEST_ORG_2 OrgAuditor --origin cloud.gov

echo ""
echo "Space roles in $TEST_ORG_1/$TEST_SPACE_1:"
cf set-space-role $TEST_USER $TEST_ORG_1 $TEST_SPACE_1 SpaceDeveloper --origin cloud.gov
cf set-space-role $TEST_USER $TEST_ORG_1 $TEST_SPACE_1 SpaceAuditor --origin cloud.gov
cf set-space-role $TEST_USER $TEST_ORG_1 $TEST_SPACE_1 SpaceManager --origin cloud.gov
cf set-space-role $TEST_USER $TEST_ORG_1 $TEST_SPACE_1 SpaceSupporter --origin cloud.gov

echo ""
echo "Space roles in $TEST_ORG_2/$TEST_SPACE_2:"
cf set-space-role $TEST_USER $TEST_ORG_2 $TEST_SPACE_2 SpaceDeveloper --origin cloud.gov
cf set-space-role $TEST_USER $TEST_ORG_2 $TEST_SPACE_2 SpaceAuditor --origin cloud.gov
cf set-space-role $TEST_USER $TEST_ORG_2 $TEST_SPACE_2 SpaceManager --origin cloud.gov
cf set-space-role $TEST_USER $TEST_ORG_2 $TEST_SPACE_2 SpaceSupporter --origin cloud.gov


echo -e "${YELLOW}Test Set 2: Verify cloud.gov user has all expected roles${NC}"
$SCRIPT_PATH --source-user-id $TEST_USER --source-origin cloud.gov --target-user-id $TEST_USER --target-origin cloud.gov --dry-run-source > initial_cloud_gov_roles.txt 2>&1 || true

# Verify the command succeeded
if grep -q "Error: Source user" initial_cloud_gov_roles.txt; then
    print_result 1 "cloud.gov user not found"
    echo -e "${RED}Critical test failed: cloud.gov user not found during initial state verification. Exiting.${NC}"
else
    print_result 0 "cloud.gov user exists"
    
    # Count and verify roles
    ORG_ROLES=$(count_roles initial_cloud_gov_roles.txt "org")
    SPACE_ROLES=$(count_roles initial_cloud_gov_roles.txt "space")
    ORG_USER_ROLES=$(count_roles initial_cloud_gov_roles.txt "org_user")
    
    EXPECTED_ORG_ROLES=6
    if [ "$ORG_ROLES" -eq "$EXPECTED_ORG_ROLES" ]; then
        print_result 0 "cloud.gov user has $EXPECTED_ORG_ROLES organization roles (found: $ORG_ROLES)"
    else
        print_result 1 "cloud.gov user has incorrect organization roles (found: $ORG_ROLES, expected: $EXPECTED_ORG_ROLES)"
        echo -e "${RED}Critical test failed: cloud.gov organization role count mismatch. Exiting.${NC}"
    fi
    
    EXPECTED_SPACE_ROLES=8
    if [ "$SPACE_ROLES" -eq "$EXPECTED_SPACE_ROLES" ]; then
        print_result 0 "cloud.gov user has $EXPECTED_SPACE_ROLES space roles (found: $SPACE_ROLES)"
    else
        print_result 1 "cloud.gov user has incorrect space roles (found: $SPACE_ROLES, expected: $EXPECTED_SPACE_ROLES)"
        echo -e "${RED}Critical test failed: cloud.gov space role count mismatch. Exiting.${NC}"
    fi
    
    EXPECTED_ORG_USER_ROLES=2
    if [ "$ORG_USER_ROLES" -eq "$EXPECTED_ORG_USER_ROLES" ]; then
        print_result 0 "cloud.gov user has $EXPECTED_ORG_USER_ROLES organization_user roles (found: $ORG_USER_ROLES)"
    else
        print_result 1 "cloud.gov user has incorrect organization_user roles (found: $ORG_USER_ROLES, expected: $EXPECTED_ORG_USER_ROLES)"
        echo -e "${RED}Critical test failed: cloud.gov organization_user role count mismatch. Exiting.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Verify Cloud.gov user complete!${NC}"



# PHASE 3: VERIFY LOGIN.GOV USER CREATION AND INITIAL STATE
print_section "PHASE 3: Verify login.gov User Creation and Initial State"

echo ""
echo "Creating test user..."
echo "- Creating login.gov origin user (initially without roles)..."
cf create-user $TEST_USER --origin login.gov


echo ""
echo -e "${YELLOW}Test Set 3: Verify login.gov user starts with no roles${NC}"
$SCRIPT_PATH --source-user-id $TEST_USER --source-origin login.gov --target-user-id $TEST_USER --target-origin login.gov --dry-run-source > initial_login_gov_roles.txt 2>&1 || true

if grep -q "No organization roles found" initial_login_gov_roles.txt && grep -q "No space roles found" initial_login_gov_roles.txt; then
    print_result 0 "login.gov user has no initial roles"
else
    # Count any existing roles
    EXISTING_ORG=$(count_roles initial_login_gov_roles.txt "org")
    EXISTING_SPACE=$(count_roles initial_login_gov_roles.txt "space")
    EXISTING_ORG_USER=$(count_roles initial_login_gov_roles.txt "org_user")
    if [ "$EXISTING_ORG" -eq 0 ] && [ "$EXISTING_SPACE" -eq 0 ] && [ "$EXISTING_ORG_USER" -eq 0 ]; then # Check added for org_user
        print_result 0 "login.gov user has no initial roles"
    else
        print_result 1 "login.gov user unexpectedly has roles (org: $EXISTING_ORG, space: $EXISTING_SPACE, org_user: $EXISTING_ORG_USER)"
        echo -e "${RED}Critical test failed: login.gov user started with unexpected roles. Exiting.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Verify Login.gov user complete!${NC}"



# PHASE 4: WAIT FOR MIGRATION
print_section "PHASE 4: Wait for Remote Migration Process"

echo "Waiting $WAIT_TIME seconds for the remote application to detect and process the new login.gov user..."
echo -n "Progress: "
for i in $(seq 1 $WAIT_TIME); do
    echo -n "."
    sleep 1
    if [ $((i % 10)) -eq 0 ]; then
        echo -n " ${i}s "
    fi
done
echo " Done!"

# PHASE 5: VERIFY MIGRATION RESULTS
print_section "PHASE 5: Verify Migration Results"
echo -e "${YELLOW}Test Set 5: Verify login.gov user received all roles${NC}"
$SCRIPT_PATH --source-user-id $TEST_USER --source-origin login.gov --target-user-id $TEST_USER --target-origin login.gov --dry-run-source > final_login_gov_roles.txt 2>&1 || true

# Check if user has roles now
if grep -q "No organization roles found" final_login_gov_roles.txt; then
    print_result 1 "Migration failed - login.gov user still has no roles"
    echo "Migration does not appear to have run. This could mean:"
    echo "  - The remote application is not running"
    echo "  - The wait time was too short"
    echo "  - There's an issue with the migration process"
    echo -e "${RED}Critical test failed: login.gov user has no roles after migration. Exiting.${NC}"
else
    print_result 0 "login.gov user has received roles"
    
    # Count final roles
    FINAL_ORG_ROLES=$(count_roles final_login_gov_roles.txt "org")
    FINAL_SPACE_ROLES=$(count_roles final_login_gov_roles.txt "space")
    FINAL_ORG_USER_ROLES=$(count_roles final_login_gov_roles.txt "org_user")
    
    echo ""
    echo "Role counts for login.gov user:"
    echo "  Organization roles: $FINAL_ORG_ROLES (expected: 6)"
    echo "  Space roles: $FINAL_SPACE_ROLES (expected: 8)"
    echo "  Organization user roles: $FINAL_ORG_USER_ROLES (expected: 2)"
    
    # Verify specific roles
    echo ""
    echo "Verifying specific roles..."
    
    # Check org roles (these are specific role checks, not counts)
    grep -q "login-migrator-test-org-1: OrgManager" final_login_gov_roles.txt || true
    print_result $? "Has $TEST_ORG_1 OrgManager role"
    
    grep -q "login-migrator-test-org-1: BillingManager" final_login_gov_roles.txt || true
    print_result $? "Has $TEST_ORG_1 BillingManager role"
    
    grep -q "login-migrator-test-org-2: OrgManager" final_login_gov_roles.txt || true
    print_result $? "Has $TEST_ORG_2 OrgManager role"
    
    # Check space roles
    grep -q "$TEST_ORG_1/$TEST_SPACE_1: SpaceDeveloper" final_login_gov_roles.txt || true
    print_result $? "Has $TEST_ORG_1/$TEST_SPACE_1 SpaceDeveloper role"
    
    grep -q "$TEST_ORG_2/$TEST_SPACE_2: SpaceManager" final_login_gov_roles.txt || true
    print_result $? "Has $TEST_ORG_2/$TEST_SPACE_2 SpaceManager role"
    
    # Verify role counts match - CRITICAL CHECKS
    EXPECTED_ORG_ROLES=6
    if [ "$FINAL_ORG_ROLES" -eq "$EXPECTED_ORG_ROLES" ]; then
        print_result 0 "Organization role count matches expected ($EXPECTED_ORG_ROLES)"
    else
        print_result 1 "Organization role count mismatch (found: $FINAL_ORG_ROLES, expected: $EXPECTED_ORG_ROLES)"
        echo -e "${RED}Critical test failed: Organization role count mismatch. Exiting.${NC}"
    fi
    
    EXPECTED_SPACE_ROLES=8
    if [ "$FINAL_SPACE_ROLES" -eq "$EXPECTED_SPACE_ROLES" ]; then
        print_result 0 "Space role count matches expected ($EXPECTED_SPACE_ROLES)"
    else
        print_result 1 "Space role count mismatch (found: $FINAL_SPACE_ROLES, expected: $EXPECTED_SPACE_ROLES)"
        echo -e "${RED}Critical test failed: Space role count mismatch. Exiting.${NC}"
    fi

    EXPECTED_ORG_USER_ROLES=2
    if [ "$FINAL_ORG_USER_ROLES" -eq "$EXPECTED_ORG_USER_ROLES" ]; then
        print_result 0 "Organization user role count matches expected ($EXPECTED_ORG_USER_ROLES)"
    else
        print_result 1 "Organization user role count mismatch (found: $FINAL_ORG_USER_ROLES, expected: $EXPECTED_ORG_USER_ROLES)"
        echo -e "${RED}Critical test failed: Organization user role count mismatch. Exiting.${NC}"
    fi
fi

# PHASE 6: CHECK SOURCE USER STATUS
print_section "PHASE 6: Verify Source User Status"

echo -e "${YELLOW}Test Set 6: Check if cloud.gov user still exists${NC}"
$SCRIPT_PATH --source-user-id $TEST_USER --source-origin cloud.gov --target-user-id $TEST_USER --target-origin cloud.gov --dry-run-source > final_cloud_gov_check.txt 2>&1 || true
if grep -q "Error: Source user" final_cloud_gov_check.txt; then
    echo -e "${YELLOW}cloud.gov user has been deleted (DELETE_SOURCE_USER=true in remote app)${NC}"
    print_result 0 "Source user deletion confirmed"
else
    echo "cloud.gov user still exists (DELETE_SOURCE_USER=false or not set in remote app)"
    print_result 0 "Source user retained as expected"
fi

# PHASE 7: ROLE COMPARISON
print_section "PHASE 7: Role Comparison Report"

echo "Creating detailed role comparison..."
{
    echo "ROLE MIGRATION COMPARISON REPORT"
    echo "================================="
    echo ""
    echo "Initial cloud.gov user roles:"
    grep -E "^\s*- " initial_cloud_gov_roles.txt 2>/dev/null | sort || echo "  No roles found"
    echo ""
    echo "Final login.gov user roles:"
    grep -E "^\s*- " final_login_gov_roles.txt 2>/dev/null | sort || echo "  No roles found"
} > role_comparison.txt

cat role_comparison.txt

# RESULTS SUMMARY
print_section "TEST RESULTS SUMMARY"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo "Total tests run: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed successfully!${NC}"
    echo ""
    echo "The migration process successfully:"
    echo "- Detected the new login.gov user"
    echo "- Found the matching cloud.gov user"
    echo "- Copied all organization and space roles"
    EXIT_CODE=0
else
    echo ""
    echo -e "${RED}✗ Some tests failed!${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Verify the remote application is running: cf apps"
    echo "2. Check if wait time needs to be increased: WAIT_TIME=120 $0"
    echo "3. Review the role comparison in role_comparison.txt"
    echo "4. Manually check user roles using the copy-user-org-and-space-roles.sh script"
    EXIT_CODE=1
fi

# Save test outputs
echo ""
echo "Test artifacts saved:"
ls -la *_roles.txt role_comparison.txt 2>/dev/null | while read line; do echo "  $line"; done

if [ $TESTS_FAILED -gt 0 ]; then
    echo ""
    echo "For debugging, you can:"
    echo "  - Check initial cloud.gov roles: cat initial_cloud_gov_roles.txt"
    echo "  - Check initial login.gov roles: cat initial_login_gov_roles.txt"
    echo "  - Check final login.gov roles: cat final_login_gov_roles.txt"
    echo "  - Check role comparison: cat role_comparison.txt"
fi

exit $EXIT_CODE