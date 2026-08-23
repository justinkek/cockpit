# ⭐ Intent

> _ADR = Architecture Decision Record_ https://github.com/joelparkerhenderson/architecture-decision-record

- Make a _**conscious**_ **decision on a software design choice** with specific requirements and context
- **succinctly explain and communicate** key information

_Typically ADRs involve decisions around architecture. In this standard, we are broadening this to any technical solution._

# 👆 Key Points

- **Problem Statement** (section)
  - → Single sentence naming the decision needed, in plain language
- **Context** (section)
  - → Background, constraints, and project-specific requirements
- **Critical performance**
  - → A key criteria to chose the tech
  - Depends on the business requirements, the client stakeholders and technicals constraints (stability, security, speed)
  - Should ideally be measurable
- **(Tech) Options**
  - → an ADR compares different tech options
  - A "_**Tech option**_" can be anything from `Java` to `Microservice Architecture` or `React.pdf`
  - Any number of options can be considered, but it is usually less that 5
- **Evaluation**
  - → Show succinct, synthesised information in a table
- **Decision**
  - → Final recommendation, based on the selected critical performance and the specific context of this situation

# ✅ Control Points

- The ADR lists the important performances and options **for my client**
- My **critical performances** are linked to outcomes
- My **critical performances** and **evaluation** of each option are **precise**
- My final recommendation is assertive

## 🤦 Common Errors

| **Errors**                                                                                          | **Consequences**                                                                                                                                    |
| --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 🚨 Identifying **too many** critical performances                                                   | The final choice would be subjective, because the critical performances won't help prioritise and settle on a single option                         |
| 🚨 Tunnelling on getting measurable critical performances when too complex                          | The return on investment of measuring performance for each option will be small, and incompatible with making a quick decision                      |
| 🚨 Setting a critical performance just to highlight your favourite solution                         | This critical performance will necessarily be biased towards a single solution                                                                      |
| 🚨 Only focusing on one kind of user of the tech (i.e. the dev)                                     | Ignoring the end-user's experience (UX, performance), or the way it will be perceived by the client's security department, will cause future rework |
| 🚨 Not looping in the people with a different opinion (when writing and getting the ADR challenged) | People who weren't involved in the decision risk being opposed to implementing the solution                                                         |
| 🚨 Make the ADR a perfect democracy                                                                 | If everyone can add / remove performances and solutions indefinitely, no decision will be made                                                      |

## 🖼️ Template

- [Template](./TEMPLATE.md)

## 📁 File naming

ADR files must be named `adr-YYYY-MM-DD-<short-description>.md`, e.g. `adr-2026-06-16-lfr-sql-schema-validation.md`.

## ⁉️ FAQ

- When should I do an ADR?
  - Most often this would be **during the tech challenge** to chose the technical architecture
  - But **any time a new feature requires a new choice**, the installation or usage or a new tech, then you should also create an ADR
