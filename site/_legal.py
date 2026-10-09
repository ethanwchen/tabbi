"""
The legal pages, as structured HTML.

These are drafts written against what Tabbi actually does (see
backend/PRIVACY.md and the README's Privacy section), not legal advice.
Have a professional read them before relying on them; site/README.md says
the same at the top.
"""

from _partials import GITHUB, SUPPORT_EMAIL

EFFECTIVE = '8 October 2026'

MAIL = f'<a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>'

# --------------------------------------------------------------------------
# Privacy
# --------------------------------------------------------------------------

PRIVACY_HERO = ('Privacy Policy', 'What stays on your Mac, what the optional friends service and account keep, and how to delete them.')

PRIVACY = f'''      <p class="eyebrow">Effective {EFFECTIVE}</p>

      <div class="card">
        <h2>The short version</h2>
        <ul>
          <li>Tabbi works without an account, and has no analytics, no advertising and no telemetry.</li>
          <li>Your tasks, calendar, activity history, Claude chats and settings stay on your Mac.</li>
          <li>Claude features run through the <code>claude</code> command already installed on your Mac. Tabbi never reads your credentials.</li>
          <li>Only the optional Party tab and the optional Sign in with Apple talk to a Tabbi server. They store a nickname, your pet and study stats, never your email, real name or IP address.</li>
          <li>We do not sell or share personal information, and we do not use it to train anything.</li>
          <li>You can delete your Party data or your account at any time, inside the app: see <a href="#deleting">Deleting your data</a>.</li>
        </ul>
      </div>

      <h2>1. Who we are</h2>
      <p class="measure">Tabbi is a free, open-source macOS app made by Ethan Chen ("we", "us"), who also runs the friends service and this website and is the controller of the little personal data described here.
        Contact {MAIL} about anything in this policy.</p>

      <h2 id="mac">2. What stays on your Mac</h2>
      <p class="measure">Most of Tabbi never leaves your computer. We cannot see any of the following, because it is never sent to us:</p>
      <ul class="measure">
        <li><strong>Tasks, plans and settings</strong> are files in <code>~/Library/Application Support/Tabbi</code> and Tabbi's preferences.</li>
        <li><strong>Calendar events</strong> are read through macOS, with your permission, to show what is next and to plan your day. Plan my day runs on your Mac. Events never leave it, except as described for Claude below.</li>
        <li><strong>Activity history</strong> (focus sessions, breaks, cards reviewed, tasks done) is a log on your Mac that powers streaks, points and your pet.</li>
        <li><strong>Claude features</strong> (Ask Claude, Refine with Claude, Wrap up) run the <code>claude</code> command-line tool you installed yourself. What you type, a screenshot you attach, or, when you press Refine or Wrap up, your task titles and today's events, are passed to that tool, which sends them to Anthropic under your own Anthropic account and Anthropic's terms. Tabbi never reads your credentials or the keychain. Chat history is saved on your Mac. Claude Usage reads token counts from <code>~/.claude/projects</code>, read-only.</li>
        <li><strong>Anki</strong> data comes from Anki on your own Mac through AnkiConnect, a local connection that does not leave the computer.</li>
        <li><strong>Spotify and Apple Music</strong> are controlled through Apple Events, with your permission. Album artwork is downloaded from the address the music app provides (for Spotify, its image server), which, like any web request, shows that server your IP address.</li>
        <li><strong>Screenshots</strong> for Ask Claude use Screen Recording permission and go only to your local <code>claude</code> command.</li>
      </ul>
      <p class="measure"><strong>Updates.</strong> Once a day Tabbi downloads its release feed from GitHub to check for a new version. Nothing about you is sent, though GitHub sees the request like any web server. You can turn this off in <strong>Settings &gt; About</strong>.</p>

      <h2 id="friends">3. The friends service (Party)</h2>
      <p class="measure">Party is optional and off unless you turn it on.
        When it is on, Tabbi talks to a small server we run on Cloudflare so you can see which friends are studying, study together in a party, and compare weekly study minutes.
        You are identified only by a random secret token (we store a one-way hash of it) and a public 8-character friend code.
        The server stores:</p>
      <div class="scroller">
        <table>
          <thead>
            <tr><th>What</th><th>Details</th><th>Kept</th></tr>
          </thead>
          <tbody>
            <tr><td>Profile</td><td>A display name of your choice (any nickname works), your pet's name, species, breed, colors, costume and accessories, points and level, and when your friend code was created.</td><td>Until you delete it</td></tr>
            <tr><td>Presence</td><td>From the last heartbeat: studying, on a break, idle or offline; the study method; when the current phase ends; minutes this session and today; your streak; your local calendar day.</td><td>Overwritten by each heartbeat; deleted with your profile</td></tr>
            <tr><td>Study minutes</td><td>Minutes per local calendar day, for the weekly leaderboard.</td><td>28 days</td></tr>
            <tr><td>Friends</td><td>The friend codes you are friends with.</td><td>Until either of you removes the friendship</td></tr>
            <tr><td>Party</td><td>The party you are in and when you joined; for the party itself, its code, host, last activity and the shared session.</td><td>Until the last member leaves, or 12 hours without activity</td></tr>
          </tbody>
        </table>
      </div>
      <p class="measure"><strong>Never collected:</strong> email addresses, real names, passwords, device names, card or deck content, note text, and IP addresses. The server rejects requests that carry anything else.
        Your local calendar day (for example 2026-10-02) can hint at your time zone; it is used only to count minutes toward the right day.
        Cloudflare, which hosts the server, sees connection details like any web host. The server uses your IP address only in memory, to limit abuse, and never stores it.</p>
      <p class="measure"><strong>Who can see it.</strong> Friends see your profile, presence, whether you are in a party, and your weekly minutes.
        Members of your party see the profile and presence of everyone in it, including people who are not their friends.
        There is no directory or search. <strong>Go invisible</strong> in the Party options shows you as offline to friends.</p>

      <h2 id="account">4. The optional account (Sign in with Apple)</h2>
      <p class="measure">Tabbi works fully without an account.
        If you choose <strong>Sign in with Apple</strong> in <strong>Settings &gt; General</strong>, your pet and progress sync across the Macs you sign in on, and your Party friend code and friends follow you.
        Tabbi asks Apple only for your name, never your email address. Your name stays on your Mac, to greet you in Settings, and is never sent to our server.
        On top of the friends service data above, the server stores:</p>
      <div class="scroller">
        <table>
          <thead>
            <tr><th>What</th><th>Details</th><th>Kept</th></tr>
          </thead>
          <tbody>
            <tr><td>Apple link</td><td>Apple's stable user id for Tabbi (an opaque id, not your email or Apple Account name), linked to your friend code.</td><td>Until you delete your account</td></tr>
            <tr><td>Apple refresh token</td><td>Kept only so we can revoke Tabbi's Sign in with Apple access when you delete your account. It is never used to read anything from Apple.</td><td>Until you delete your account</td></tr>
            <tr><td>Mac tokens</td><td>One random secret token per Mac you signed in on, stored as a one-way hash.</td><td>Until you delete your account</td></tr>
            <tr><td>Sync document</td><td>Your pet's look (species, breed, name, outfit), points earned and spent on each Mac (each Mac is a random id, not its name), the items you unlocked, the days you studied (at most the last 400) and your longest streak.</td><td>Until you delete your account</td></tr>
          </tbody>
        </table>
      </div>
      <p class="measure">Your calendar, tasks, activity history, Claude chats and settings are never synced.
        Nobody but you can see your sync document or Apple link, friends included.
        To check a sign-in, and to revoke it when you delete your account, the server talks to Apple and sends only the token or code Apple gave the app.
        If you sign in on a Mac that already had a friend code of its own, its friends and study minutes move to your account and the old code is deleted.
        <strong>Sign Out</strong> stops syncing on that Mac and keeps your pet and progress there.</p>

      <h2 id="deleting">5. Deleting your data</h2>
      <p class="measure"><strong>On your Mac.</strong> Everything Tabbi keeps locally is yours to delete. Quit Tabbi, drag it to the Trash, and delete
        <code>~/Library/Application Support/Tabbi</code> and Tabbi's preferences
        (the <a href="{GITHUB}/blob/main/docs/install.md#uninstall">install guide</a> lists every folder).
        Ask Claude chats can also be deleted one by one, or all at once, inside the app.</p>
      <p class="measure"><strong>Party, in the app.</strong></p>
      <ul class="measure">
        <li><strong>Leave a party</strong> from the Party tab. Your membership is removed at once, and a party is deleted when its last member leaves or after 12 hours without activity.</li>
        <li><strong>Remove a friend</strong> from their card in the Party tab. The friendship is deleted on both sides.</li>
        <li><strong>Turn Party off</strong> in <strong>Settings &gt; Tabs</strong> to stop sending anything. Friends then see you as offline.</li>
        <li>Daily study minutes are deleted automatically after 28 days.</li>
      </ul>
      <p class="measure"><strong>Party, everything.</strong> Without an account, open <strong>Settings open <strong>Settings &gt; Party</strong> and choose <strong>Delete my Party data</strong>gt; Tabs</strong>, click <strong>Options</strong> next to Party, and choose <strong>Delete my Party data</strong>.
        The server erases your friend code, profile, presence, study minutes and friend list at once, removes you from your friends' lists and your party, and invalidates your secret token.
        Your pet and points stay on your Mac, and if Party stays on, you get a new friend code.</p>
      <p class="measure"><strong>Your account.</strong> When signed in, open <strong>Settings &gt; General</strong> and choose <strong>Delete Account</strong>.
        The server erases everything above at once: your Party data, your sync document, your Apple link and the tokens of every Mac you signed in on.
        It then revokes Tabbi's Sign in with Apple access with Apple. Your pet and progress stay on the Mac you deleted from.</p>
      <p class="measure"><strong>By email.</strong> If you can no longer use the app, email {MAIL} with your friend code (it is shown in the Party tab).
        To make sure the request is yours, we may ask you to change your Party nickname to a word we send you.
        We then delete the same data within 30 days, usually much sooner, and confirm by email.</p>

      <h2>6. This website</h2>
      <p class="measure">tabbinotch.com has no cookies, no analytics and no scripts.
        It is hosted on Cloudflare Pages, which processes the requests your browser makes, including your IP address, to serve and protect the site.
        If you email us, we use your message and address only to reply, and delete the thread when it is no longer needed.</p>

      <h2>7. Why we are allowed to</h2>
      <p class="measure">Where the GDPR or UK GDPR applies, we process friends-service and account data to provide the features you turned on (Article 6(1)(b)) and in our legitimate interest in keeping the service secure and free of abuse (Article 6(1)(f)).
        We answer email on the basis of our legitimate interest in helping you.</p>

      <h2>8. Who else is involved</h2>
      <p class="measure">We use Cloudflare to host the friends service and this website.
        If you sign in with Apple, Apple checks the sign-in and, when you delete your account, revokes it.
        We do not sell, rent or share personal information with anyone else, and nothing is used for advertising or to train machine-learning models.
        We would disclose data only if the law required it, and the friends service holds very little to disclose.
        Cloudflare's network is global, so data may be processed outside your country, under Cloudflare's standard contractual clauses where those apply.</p>

      <h2>9. Your rights</h2>
      <p class="measure">Wherever you live, you can ask us to tell you what we hold about you, correct it, give you a copy, or delete it, and you can object to how we use it. Email {MAIL}; we answer within 30 days. <a href="#deleting">Deleting your data</a> explains deletion step by step.
        You can change your nickname and pet, and delete your Party data or account, in the app yourself, at any time.</p>
      <h3>Europe and the UK</h3>
      <p class="measure">Under the GDPR and UK GDPR you have the rights of access, rectification, erasure, restriction, portability and objection, and the right to complain to your local data protection authority.</p>
      <h3>California</h3>
      <p class="measure">Under the CCPA as amended by the CPRA you have the right to know, delete and correct personal information, and to not be treated differently for using these rights.
        We do not sell or share personal information as those laws define it, and we do not use sensitive personal information.</p>

      <h2>10. Security</h2>
      <p class="measure">Traffic to the friends service is encrypted with HTTPS, your secret tokens are stored only as hashes, and the service keeps the minimum it needs.
        No system is perfectly secure; if we learn of a breach affecting you, we will say so on this site and on GitHub as quickly as we can.</p>

      <h2>11. Children</h2>
      <p class="measure">Tabbi is not directed at children under 13, and we do not knowingly collect their personal information.
        If you believe a child has used Party, email us and we will delete their data.</p>

      <h2>12. Changes</h2>
      <p class="measure">If this policy changes, we will update the date at the top and keep the history in the
        <a href="{GITHUB}">Tabbi repository</a>. We will not start collecting new kinds of personal data without saying so here first.</p>
'''

# --------------------------------------------------------------------------
# Terms
# --------------------------------------------------------------------------

TERMS_HERO = ('Terms of Use', 'Short, because Tabbi is free and open source.')

TERMS = f'''      <p class="eyebrow">Effective {EFFECTIVE}</p>

      <div class="card">
        <h2>The short version</h2>
        <ul>
          <li>Tabbi is free and open source under the MIT License.</li>
          <li>It comes as is, with no warranty.</li>
          <li>Be decent in Party: no offensive names, no abuse of the service.</li>
        </ul>
      </div>

      <h2>1. Who these terms are with</h2>
      <p class="measure">These terms are between you and Ethan Chen ("we", "us"), who makes Tabbi and runs the friends service and this website.
        By using Tabbi, the friends service or tabbinotch.com you agree to them. If you do not agree, please do not use them.</p>

      <h2>2. The app and its license</h2>
      <p class="measure">The Tabbi app and its source code are licensed under the <a href="{GITHUB}/blob/main/LICENSE">MIT License</a>.
        That license, not these terms, governs what you may do with the code: use, copy, modify and distribute it, keeping the copyright and license notice.
        These terms add only what the license does not cover: the friends service and the website.</p>
      <p class="measure">The name Tabbi and the cat icon identify this project. Please do not use them in a way that suggests your fork or product is the official Tabbi.</p>

      <h2>3. Other services</h2>
      <p class="measure">Some tabs work with software and services from others: Claude (through your own <code>claude</code> command and Anthropic account), Anki and AnkiConnect, Spotify, Apple Music and your calendar.
        Their own terms apply to your use of them, and we are not responsible for them.</p>

      <h2>4. The friends service</h2>
      <p class="measure">Party uses a free server we run. While using it, you agree not to:</p>
      <ul class="measure">
        <li>choose a display name or pet name that is hateful, harassing, sexually explicit or impersonates someone;</li>
        <li>harass other people, or join parties you were not invited to in order to disrupt them;</li>
        <li>overload, probe, scrape or attack the service, or get around its limits;</li>
        <li>use it for anything unlawful.</li>
      </ul>
      <p class="measure">We may remove names, friendships or parties, or block a user, when we believe these terms were broken.
        The service is offered for free and may change, be limited or stop at any time; we will try to give notice on GitHub first.
        The <a href="/privacy#friends">privacy policy</a> explains what it stores and how to delete it.</p>

      <h2>5. No warranty</h2>
      <p class="measure">Tabbi, the friends service and this website are provided "as is" and "as available", without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose and non-infringement.
        Timers, reminders, plans and Claude's answers can be wrong or late. Do not rely on Tabbi for anything where a missed alert or a wrong answer could cause harm.</p>

      <h2>6. Limitation of liability</h2>
      <p class="measure">To the fullest extent the law allows, we are not liable for any indirect, incidental, special, consequential or punitive damages, or for lost data, profits or time, arising from your use of Tabbi, the friends service or this website.
        Because all of them are free, our total liability for any claim is limited to 50 US dollars.
        Some places do not allow these limits, so they may not apply to you, and nothing here limits rights you have by law that cannot be waived.</p>

      <h2>7. Governing law</h2>
      <p class="measure">These terms are governed by the laws of the State of New York, United States, without regard to its conflict of law rules.
        Any dispute that cannot be settled informally will be heard in the state or federal courts located in New York, New York, unless the law where you live gives you the right to bring it there.</p>

      <h2>8. Changes</h2>
      <p class="measure">We may update these terms. When we do, we will change the date at the top and keep the history in the <a href="{GITHUB}">Tabbi repository</a>.
        If you keep using Tabbi after a change, the new terms apply.</p>

      <h2>9. Contact</h2>
      <p class="measure">Questions about these terms: {MAIL}.</p>
'''
