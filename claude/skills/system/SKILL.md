---
name: system
description: How every session works with {{NAME}}'s vault and setup. Use it whenever the work touches the vault, the hooks, the rules, memory, a correction, a decision, or how the work itself is done: "remember this", "that's wrong", "from now on", "why did you do that", "fix the setup", "is it actually fixed". Also use it before proposing any new tool, platform, price or plan.
---

# How work is done and remembered

Facts live in the vault (`{{VAULT}}`, read `DECISIONS.md` first). Rules live here, and each one names the check that enforces it. A rule with no check is advisory and says so.

1. **Verify by running, not by reading.** Running code beats live output, which beats a document, which beats memory. If you could not run it, write "not verified". A green test only proves something if the test actually ran.

2. **A fix is not done until something catches the next time.** Fix the cause, then add the test, hook or check that would have caught it. If none is possible, say the fix is unguarded.

3. **Read `DECISIONS.md` before choosing a tool, platform, price or plan.** Find the question, read its row in the area file under `decisions/`. If it is answered, apply the answer. If you decide something new, add one row in the same turn: the answer in about 60 words, the date, and a link to the note with the reasoning. Check: none, advisory.

4. **A correction is finished when `RETRACTED.md` holds the dead phrase**, one phrase per table row, and every note that still said it is changed the same turn. Check: `hooks/save-check` searches every living note for the old wording and writes the row itself; `hooks/retracted-check` flags a prose entry or a broken row at the next message.

5. **Never state a number a tool did not read this session.** An empty result is not a reading either: name what could produce the same blank (a permission, a filter) before calling something absent, or say "could not see it". Another tool's report is a document too: check the thing itself. Check: none, advisory.

6. **Never send, publish, pay, subscribe or touch legal wording without a yes.** Draft it, stop at the button, ask. Check: `hooks/source-check` makes the session open the rule's note before a send, publish, price or legal edit.

7. **Plain language, no em dashes, sound like a person.** Check: none, advisory.

8. **Write the fact, not the feeling.** Something worth keeping goes in the vault the moment it is said, in the note that owns the topic. **A new fact is saved only when the old one is gone.** Check: `hooks/save-check` runs at the end of every turn. It asks what is true now (counting what the session did, not only what {{NAME}} said), and a save must name what it replaced: `REPLACED: <old wording> => <what is true now>` or `REPLACED: nothing`. It searches every living note for the old wording and will not let the turn end while one still says it (three asks at most). Answer in the reply, with only those lines, no recap.
   - A note read whole stays under 3,000 words; past that the dated story moves to `<note>-history.md`. Check: `hooks/note-size`.
   - Another note is linked as `[[folder/name]]`, never a backticked file name. Check: `hooks/graph-repair`, run by the autosave hook, flags a note with no link in or out.
   - A dated research note is history, not the answer. Check: `hooks/newer-facts` shows newer decisions and retractions when one is opened.
   - The hard rules ride in every session as their own block (`hooks/session-start`). Check: `hooks/hard-rules.test.sh` fails when a quote is no longer in its note.

9. **The vault backs itself up.** `hooks/vault-autocommit.sh` commits every change at the end of each turn and pushes to {{NAME}}'s private GitHub repo when it can do so cleanly. If the push is refused, the next message says so; fix that before writing more memory.

10. **Stop a process by its PID or port, never `pkill -f`.**

If a rule above turns out to be wrong, change it here and name what replaced it; never add a second rule beside it.
