# Haptic Feedback Guidelines

This guide provides principles and guidelines for using haptic feedback in user interfaces to enhance the user experience through tactile feedback.

## Overview

Haptic feedback provides physical confirmation of user actions through device vibration. When used thoughtfully and consistently, it enhances usability by providing non-visual feedback that guides users and confirms their interactions. However, overuse can be distracting and reduce the effectiveness of haptic feedback.

## Haptic Feedback Types

### Selection Feedback
**`HapticsType.selection`** - Use for selection actions where users are choosing from options or making a choice.

**When to use:**
- Selecting items from lists or menus
- Choosing options in pickers or dropdowns
- Toggling between states (radio buttons, checkboxes)
- Switching between tabs or sections
- Making choices from multiple options

**Characteristics:**
- Provides confirmation that a selection has been made
- Should feel responsive and immediate
- Used for discrete selection actions

### Navigation Feedback
**`HapticsType.light`** - Use for general navigation and routine interactions.

**When to use:**
- Navigating between screens or pages
- Opening modals, sheets, or overlays
- General button interactions
- Routine, non-critical actions
- Secondary navigation elements

**Characteristics:**
- Subtle and unobtrusive
- Should not distract from the primary action
- Consider omitting for frequently-used navigation to reduce feedback noise

### Action Result Feedback

#### Success Feedback
**`HapticsType.success`** - Use when an action completes successfully.

**When to use:**
- Successful completion of important actions
- Confirmation of transactions or payments
- Successful data synchronization
- Successful form submissions
- Achievement of goals or milestones

**Characteristics:**
- Provides positive reinforcement
- Should feel satisfying and confirmatory
- Use sparingly for truly significant successes

#### Error Feedback
**`HapticsType.error`** - Use when an action fails or encounters an error.

**When to use:**
- Failed transactions or operations
- Validation errors
- Network or connection failures
- Invalid input or actions
- System errors

**Characteristics:**
- Should alert the user to the problem
- More noticeable than success feedback
- Helps users understand that action was not completed

#### Warning Feedback
**`HapticsType.warning`** - Use for warnings or situations requiring user attention.

**When to use:**
- Confirmation dialogs for potentially destructive actions
- Insufficient resources (balance, storage, etc.)
- Important notices or alerts
- Actions that require user confirmation
- Potentially risky operations

**Characteristics:**
- Draws attention without being alarming
- Indicates caution is needed
- Should prompt user to review before proceeding

### Intensity Levels

#### Light Feedback
**`HapticsType.light`** - Subtle, gentle feedback for routine interactions.

**When to use:**
- Most common interactions
- Non-critical actions
- Frequent user actions
- General navigation

#### Medium Feedback
**`HapticsType.medium`** - Moderate feedback for more important actions.

**When to use:**
- Actions of moderate importance
- Actions that require user attention but aren't critical
- Secondary important interactions

#### Heavy Feedback
**`HapticsType.heavy`** - Strong, pronounced feedback for critical actions.

**When to use:**
- Critical or irreversible actions
- High-value transactions
- Important confirmations
- Actions with significant consequences
- Use sparingly to maintain impact

### Texture-Based Feedback

#### Rigid Feedback
**`HapticsType.rigid`** - Sharp, rigid texture feedback.

**When to use:**
- Rarely used
- Specific UI contexts where sharp, precise feedback is needed
- Specialized interactions

#### Soft Feedback
**`HapticsType.soft`** - Soft, gentle texture feedback.

**When to use:**
- Rarely used
- Specific UI contexts where gentle, smooth feedback is needed
- Specialized interactions

## Usage Guidelines

### Selection Actions
Selection haptics should be used consistently for all selection interactions. This includes:
- List item selections
- Option pickers
- Tab navigation
- Toggle switches
- Radio buttons and checkboxes

**Principle:** Every selection action should provide the same type of haptic feedback to create a consistent experience.

### Navigation Actions
Navigation haptics should be subtle and used selectively:
- Primary navigation elements may benefit from haptic feedback
- Frequently-used navigation may omit haptics to reduce feedback noise
- Secondary navigation can use light haptics
- Consider the frequency of use when deciding whether to include haptics

**Principle:** Navigation haptics should enhance, not distract. Less is often more.

### Action Results
Action result haptics provide feedback about the outcome of an action:
- Success haptics confirm positive outcomes
- Error haptics alert to problems
- Warning haptics draw attention to important information
- Use result haptics for actions with clear outcomes

**Principle:** Match haptic feedback to the importance and nature of the action result.

### Intensity Selection
Choose intensity based on action importance:
- **Light:** Routine, frequent actions
- **Medium:** Moderately important actions
- **Heavy:** Critical, high-stakes actions

**Principle:** Reserve stronger haptics for more important actions to maintain their impact.

## Best Practices

### 1. Consistency
Use the same haptic type for similar actions throughout the application. Users learn to associate specific haptic patterns with specific types of actions.

### 2. Appropriate Timing
Trigger haptic feedback at the right moment:
- Selection haptics should occur when the selection is made
- Result haptics should occur when the outcome is known
- Navigation haptics should occur when navigation is initiated

### 3. Avoid Overuse
Haptic feedback should enhance the experience, not overwhelm it:
- Not every interaction needs haptic feedback
- Consider omitting haptics for very frequent actions
- Balance feedback with user comfort

### 4. Context Awareness
Consider the context when choosing haptic types:
- More important actions deserve stronger feedback
- Routine actions should use lighter feedback
- Critical actions may require heavy feedback

### 5. User Control
Always check device capability before triggering haptic feedback. Respect user preferences and device limitations.

### 6. Testing
Test haptic feedback on physical devices, as simulators cannot reproduce haptic sensations. Ensure feedback feels appropriate and enhances the user experience.

## Decision Framework

When deciding whether to add haptic feedback to an interaction, consider:

1. **Type of Action**
   - Is this a selection, navigation, or action result?
   - What category does this interaction fall into?

2. **Importance**
   - How important is this action?
   - Does it warrant user attention through haptics?

3. **Frequency**
   - How often will users perform this action?
   - Will frequent haptics become annoying?

4. **Context**
   - What is the user trying to accomplish?
   - Does haptic feedback enhance or distract from the goal?

5. **Consistency**
   - Are similar actions using haptic feedback?
   - Will this create a consistent experience?

## Common Patterns

### Selection Pattern
- **Action:** User selects an option from a list
- **Haptic:** `selection`
- **Timing:** When selection is confirmed

### Navigation Pattern
- **Action:** User navigates to a new screen
- **Haptic:** `light` (optional, consider frequency)
- **Timing:** When navigation is initiated

### Success Pattern
- **Action:** User completes an important action successfully
- **Haptic:** `success`
- **Timing:** When success is confirmed

### Error Pattern
- **Action:** User action fails or encounters an error
- **Haptic:** `error`
- **Timing:** When error is detected

### Warning Pattern
- **Action:** User attempts potentially risky action
- **Haptic:** `warning`
- **Timing:** When warning is displayed

## Implementation

Always check device capability before triggering haptic feedback. Haptic feedback should be triggered on `onTapDown` for immediate feedback:

```dart
import 'package:haptic_feedback/haptic_feedback.dart';

// Basic usage pattern
GestureDetector(
  onTapDown: (_) async {
    final canVibrate = await Haptics.canVibrate();
    if (canVibrate) {
      await Haptics.vibrate(HapticsType.selection);
    }
  },
  onTap: () {
    // Perform your action here
    performAction();
  },
  // ...
)
```

## References

- iOS Human Interface Guidelines - Haptic Feedback
- Material Design - Haptic Feedback Patterns
- Platform-specific haptic feedback documentation
