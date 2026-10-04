# The first-day interview

You are about to interview {{NAME}} so that every future session already knows who {{NAME}} is. Fifty questions in ten sections, about 40 minutes. Read this whole file before asking anything.

## How to run it

- **One section at a time, 3 to 5 questions per message.** Number them as written below so {{NAME}} can answer by number.
- **Use clickable choices (the AskUserQuestion tool) when the answers are predictable** (marked *choices* below, with the options to offer). Everything else is open: ask it in plain text.
- **{{NAME}} can type "skip" for any question, or "later" to stop.** Never push a skipped question.
- **At most one follow-up per question**, and only when an answer is too vague to act on ("depends", "kinda"). Never interrogate.
- **Save after every section, before asking the next one.** Write facts in the notes listed for that section, in plain sentences, in {{NAME}}'s terms. Never paste a transcript. Then add one line to `.claude/interview-progress.md` in the vault: `section N: done YYYY-MM-DD` (or `skipped`).
- **Resuming:** if `.claude/interview-progress.md` exists, start at the first section not listed, and say so in one line.
- Write like a person: short, friendly, no em dashes, no "Great answer!". A quick reaction to an answer is fine; a paragraph is not.
- Before section 1, say in two lines what this is, that it takes about 40 minutes, and that "skip" and "later" work any time.

## The questions

### 1. Basics → `personal/about-me.md` (section "Basics")
1. What name do you go by?
2. How old are you, and where do you live?
3. Who do you live with, and who are the people who matter most in your day to day?
4. What does a normal weekday look like, from waking up to going to sleep?
5. What does a normal weekend look like?

### 2. Work and Duo Vert → `duo-vert/company.md`
6. In your own words, what is Duo Vert and what's your part in it?
7. Which parts of the business do you like doing, and which ones do you put off?
8. What are you better at than Emile, and what is he better at?
9. What do you handle on your own (ads, clips, clients, the Drive), and which tools and accounts do you use for it?
10. Where do the leads come from right now, and what works best?
11. What worries you most about the business for 2027?
12. Any other job, school or income besides Duo Vert?

### 3. School → `school/overview.md`
13. Are you in school? What program and year, and which courses this semester?
14. For school work, do you want me to explain, check your work, or help you draft? *choices: Explain it so I understand / Check what I wrote / Help me draft / Depends on the course*
15. What are your school's rules on using AI that I should respect?

### 4. Goals → `personal/about-me.md` (section "Goals")
16. Where do you want to be in 1 year? In 5?
17. What does success mean to you personally, outside the business?
18. What are you working toward this month?
19. What have you been meaning to start for a while and haven't?
20. What would you do with 10 extra hours a week?
21. Are you saving toward anything right now?

### 5. How you think and decide → `personal/about-me.md` (section "How {{NAME}} thinks")
22. When you have a big decision, how do you make it? *choices: Gut feeling / Research first / Ask someone I trust / Mix*
23. Who do you go to for advice, and on what?
24. A decision you're proud of, and one you regret?
25. A strong opinion you hold that most people disagree with?
26. When you're wrong, do you want me to push back? How hard? *choices: Hard, tell me straight / Firm but short / Gently / Only if it really matters*
27. When you're stressed or overwhelmed, what does it look like, and what helps?

### 6. How you want me to talk to you → `feedback/how-i-want-answers.md`
28. Short answers or detailed ones by default? *choices: Short, I'll ask for more / Medium / Detailed / Short for quick stuff, detailed for big stuff*
29. Bullet points or plain sentences? *choices: Bullets / Sentences / Mix*
30. Should I ask before doing something, or just do it and show you? *choices: Just do it and show me / Ask for big stuff only / Always ask first*
31. What did ChatGPT or Gemini do that annoyed you?
32. What did they do that you liked and want to keep?
33. Any words, tone or habits you can't stand in AI writing?
34. When I write things you'll send (texts, emails, posts), should they sound like you? Paste one or two things you wrote so I learn your style.
   (Save the style notes, never the pasted messages themselves, in `feedback/how-i-want-answers.md` under "{{NAME}}'s own voice".)

### 7. Interests and life → `personal/about-me.md` (section "Life and interests")
35. What do you do for fun?
36. Sports or training: what, how often, any goals?
37. Food: diet, allergies, what you cook?
38. What are you into right now (shows, music, games, creators)?
39. Any trips coming up or planned?
40. Something you want to learn this year?

### 8. Tech and tools → `personal/about-me.md` (section "Devices and accounts") and `decisions/tech.md`
41. What phone and laptop do you have, and which apps do you live in every day?
42. Which accounts are yours alone, and which are shared with Emile (Duo Vert Gmail, Meta, Drive)?
43. How comfortable are you with tech? *choices: Give me every click / Some steps are fine / I'm comfortable, keep it short*
44. What did you mostly use ChatGPT and Gemini for? Your top 5 uses.
45. Do you want to bring your old history in? *choices: Memory only, the 1-minute way / Full conversations turned into notes / Nothing, start fresh*
   - **Memory only:** give these numbered steps: 1) on the phone or computer, open claude.com/import-memory while signed in, 2) copy the prompt it shows, 3) paste it into ChatGPT, then into Gemini, 4) paste each answer back where Claude asks. Then also ask: "Want me to read what it gave you and add the useful parts to your vault?" and if yes, have it pasted here and save facts (not the text) into the right notes.
   - **Full conversations:** follow "Importing old conversations" at the bottom of this file. It needs the export files, which take a few hours to arrive, so give the steps now and carry on with the interview; do the import in a later session.
   - **Nothing:** record it in `decisions/tech.md` and move on.

### 9. Boundaries → `feedback/accounts-and-sending.md` (only additions) and `decisions/life.md`
46. What should I never do without asking you first? Show the defaults first, in one line: sending anything, posting, buying, deleting, signing in, touching legal wording. Then ask what to add.
47. Anything off limits: topics, or things you don't want saved in your vault?
   (Write each limit as a rule in `feedback/accounts-and-sending.md` and follow it from this moment.)
48. Emile has his own separate Claude. Is there anything you'd ever want shared with him, like Duo Vert notes later on?
   (Record the answer as a row in `decisions/duo-vert.md`. Nothing is shared unless {{NAME}} says so.)

### 10. Closing → `personal/about-me.md` and `TODO.md`
49. What's one thing people usually get wrong about you that I should get right?
50. What's the first real thing you want us to work on together?

## When all ten sections are done

1. Rewrite `personal/about-me.md` so it reads as one clear note (Basics, Goals, How {{NAME}} thinks, Life and interests, Devices and accounts), with no "not done yet" line left in it or in the other notes the interview filled.
2. Read back about 10 lines: "Here's who I think you are." Ask what's wrong or missing, and fix the notes right away.
3. Remove the interview line from `TODO.md`, and add question 50's answer as the first real item.
4. Offer to start on question 50 now.

## Importing old conversations (only if chosen at question 45)

The raw export files never go into the vault's history: they stay in `imports/`, which the vault's `.gitignore` keeps off GitHub.

1. Give {{NAME}} the steps to request the exports, as numbered clicks:
   - ChatGPT: Settings, Data controls, Export data, Confirm. An email arrives with a zip, usually within a few hours.
   - Gemini: takeout.google.com, "Deselect all", then check "Gemini" if it is listed; if not, check "My Activity", click "All activity data included", keep only "Gemini Apps", OK. Then Next step, Create export. (Google changes this page often: if it looks different, read what {{NAME}} sees before guessing.)
2. Once the zips are downloaded on the Chromebook, they are in the Downloads folder. Ask {{NAME}} to right-click Downloads in the Files app and choose "Share with Linux" (one time only). Then find them yourself under `/mnt/chromeos/MyFiles/Downloads/`.
3. Unzip into `imports/` in the vault and run `node <vault>/.claude/skills/system/import-history.mjs <vault>/imports` . It writes one plain-text digest per conversation into `imports/digests/`, newest first, with an index.
4. Read the digests in batches, newest first. From each batch, keep only what a future session would act on: facts about {{NAME}}, preferences, ongoing projects, decisions already made, things {{NAME}} corrected. Save them into the right notes like any other fact. Skip one-off questions (recipes, homework answers, trivia).
5. Track progress in `.claude/interview-progress.md` (`import: read up to <date>`), so the import can stop and resume. On the Pro plan, expect two or three sessions for a big history; say so.
6. When done, ask {{NAME}} whether to delete the raw files in `imports/` (they are not backed up anywhere else).
