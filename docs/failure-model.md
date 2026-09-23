# Failure Model

This document records deliberate failure scenarios used for reliability
testing and incident response practice.

## Format

Each failure scenario should be documented using this structure:

**Symptom** → What was observed?
**Evidence** → Logs, metrics, alerts that confirmed it.
**Hypothesis** → What did we think was wrong?
**Test** → How did we verify the hypothesis?
**Root Cause** → What actually caused the failure?
**Fix** → How was it resolved?
**Prevention** → How do we prevent recurrence?

---

## Planned Scenarios

- Pod crashes
- OOMKilled containers
- Node failure
- DNS failure
- Broken Service (wrong selector)
- NetworkPolicy blocking traffic
- Failed rollout
- Vault outage
- CPU saturation
- Application latency spike

Scenarios will be added here as the platform matures.
