# Deadline Enforcer Smart Contract

A robust Stacks blockchain smart contract for managing tasks with deadlines, automatic penalties, and reward systems. This contract enables trustless task management with built-in enforcement mechanisms and dispute resolution.

## Features

### Core Functionality
- **Task Creation**: Create tasks with defined deadlines, rewards, and penalties
- **Automatic Enforcement**: Built-in deadline tracking with penalty mechanisms
- **Escrow System**: Secure fund holding until task completion or deadline expiration
- **Reputation System**: Track user performance and build trust scores
- **Dispute Resolution**: Optional arbiter system for handling conflicts
- **Extension Requests**: Flexible deadline management with approval mechanisms

### Security Features
- **Multi-party Validation**: Creator, assignee, and optional arbiter roles
- **Deposit Requirements**: Both parties stake funds to ensure commitment
- **Platform Fees**: Sustainable contract operation with configurable fee structure
- **Access Controls**: Role-based permissions for all critical functions

## Contract Architecture

### Data Structures

#### Tasks
Each task contains:
- Creator and assignee principals
- Title and description (up to 100 and 500 characters)
- Deadline (block height)
- Reward and penalty amounts
- Status tracking
- Optional evidence URL and arbiter

#### User Statistics
- Tasks created, completed, and failed
- Total rewards earned and penalties paid
- Reputation score (starts at 100, adjusts based on performance)

#### Extensions & Disputes
- Extension tracking (max 3 per task, 1440 blocks each)
- Dispute resolution with arbiter involvement

## Usage Guide

### 1. Creating a Task

```clarity
(create-task 
    assignee-principal
    "Task Title"
    "Detailed task description"
    deadline-block-height
    reward-amount
    penalty-amount
    (some arbiter-principal)) ;; optional
```

**Requirements:**
- Deadline must be in the future
- Reward amount must be > 0
- Creator deposits reward + platform fee upfront

### 2. Accepting a Task

```clarity
(accept-task task-id)
```

**Requirements:**
- Must be called by the assigned user
- Task must be in "pending" status
- Deadline must not have passed
- Assignee deposits penalty amount (if specified)

### 3. Completing a Task

```clarity
(complete-task task-id "https://evidence-url.com")
```

**Requirements:**
- Must be called by assignee
- Must be before deadline
- Requires evidence URL

### 4. Verifying and Releasing Payment

```clarity
(verify-and-release-payment task-id)
```

**Requirements:**
- Must be called by creator or arbiter
- Task must be marked as completed
- Releases reward to assignee and returns penalty deposit

### 5. Claiming Penalties

```clarity
(claim-penalty task-id)
```

**Requirements:**
- Must be called by creator
- Deadline must have passed
- Task must still be pending (not completed)
- Transfers penalty to creator, returns reward deposit

## Task Lifecycle

```
1. Created (pending) → 2. Accepted → 3. Completed → 4. Verified & Paid
                    ↘              ↗
                      → Expired → Penalty Claimed
```

## Advanced Features

### Deadline Extensions

```clarity
(request-extension task-id new-deadline "Extension reason")
```

- Maximum 3 extensions per task
- Each extension limited to 1440 blocks (~10 days)
- Auto-approved if within limits

### Dispute Resolution

```clarity
;; Raise dispute
(raise-dispute task-id "Dispute reason")

;; Resolve dispute (arbiter only)
(resolve-dispute task-id "Resolution details" favor-assignee-bool)
```

### Task Cancellation

```clarity
(cancel-task task-id)
```

- Only before task acceptance
- Refunds creator deposit minus cancellation fee

## Fee Structure

- **Platform Fee**: 2.5% (250 basis points) of reward amount
- **Cancellation Fee**: Same as platform fee percentage
- **Maximum Fee**: Capped at 10% (admin configurable)

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | ERR-OWNER-ONLY | Admin function access denied |
| u101 | ERR-NOT-FOUND | Task or resource not found |
| u102 | ERR-ALREADY-EXISTS | Duplicate operation attempted |
| u103 | ERR-DEADLINE-PASSED | Action attempted after deadline |
| u104 | ERR-INVALID-DEADLINE | Invalid deadline specification |
| u105 | ERR-INSUFFICIENT-FUNDS | Insufficient balance for operation |
| u106 | ERR-UNAUTHORIZED | Unauthorized access attempt |
| u107 | ERR-ALREADY-COMPLETED | Task already in final state |
| u108 | ERR-NOT-COMPLETED | Task not yet completed |
| u109 | ERR-INVALID-AMOUNT | Invalid amount specified |
| u110 | ERR-TASK-CANCELLED | Operation on cancelled task |
| u111 | ERR-ALREADY-CLAIMED | Penalty already claimed |
| u112 | ERR-NO-PENALTY | No penalty available to claim |

## Read-Only Functions

### Task Information
- `get-task(task-id)` - Get complete task details
- `get-task-deposits(task-id)` - Get deposit information
- `get-task-extensions(task-id)` - Get extension history
- `get-dispute-info(task-id)` - Get dispute details

### User Information
- `get-user-stats(user)` - Get user performance statistics

### Platform Information
- `get-platform-fee-percentage()` - Current platform fee rate
- `get-total-fees-collected()` - Total platform revenue
- `get-task-count()` - Total tasks created

## Admin Functions

### Fee Management
```clarity
(set-platform-fee new-fee-basis-points)
(withdraw-fees amount recipient)
```

**Requirements:**
- Only contract owner can execute
- Fee limited to maximum 10%
- Withdrawal amount cannot exceed collected fees

## Security Considerations

### Fund Safety
- All user deposits held in contract escrow
- Automatic release mechanisms prevent fund lockup
- Platform fees collected separately from user funds

### Access Control
- Role-based permissions for all state changes
- Multi-signature support through arbiter system
- Owner-only admin functions

### Economic Incentives
- Reputation system encourages good behavior
- Penalty system discourages deadline violations
- Platform fees ensure sustainable operation

## Deployment Requirements

### Stacks Blockchain
- Compatible with Stacks 2.0+
- Requires STX for transaction fees
- Smart contract written in Clarity

### Initial Configuration
- Platform fee: 2.5% (adjustable by admin)
- Maximum extensions: 3 per task
- Maximum extension duration: 1440 blocks each

## Integration Examples

### Frontend Integration
```javascript
// Create task
await contractCall({
  contractAddress: 'SP1234...',
  contractName: 'deadline-enforcer',
  functionName: 'create-task',
  functionArgs: [
    principalCV(assignee),
    stringAsciiCV(title),
    stringAsciiCV(description),
    uintCV(deadline),
    uintCV(rewardAmount),
    uintCV(penaltyAmount),
    someCV(principalCV(arbiter))
  ]
});
```

### Task Monitoring
```javascript
// Get task status
const task = await contractCallReadOnly({
  contractAddress: 'SP1234...',
  contractName: 'deadline-enforcer',
  functionName: 'get-task',
  functionArgs: [uintCV(taskId)]
});
```

## Best Practices

### For Task Creators
1. Set realistic deadlines with buffer time
2. Provide clear, detailed task descriptions
3. Choose appropriate reward/penalty ratios
4. Consider using arbiters for high-value tasks

### For Task Assignees
1. Only accept tasks you can realistically complete
2. Request extensions early if needed
3. Provide comprehensive evidence upon completion
4. Maintain good reputation for future opportunities

### For Arbiters
1. Remain impartial in dispute resolution
2. Review all evidence thoroughly
3. Provide clear resolution explanations
4. Build reputation for fair judgments

## Contributing

This smart contract is designed for production use but may benefit from:
- Additional testing scenarios
- Gas optimization
- Enhanced dispute resolution mechanisms
- Integration with external oracle systems