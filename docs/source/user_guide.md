# User Guide

This page is for the **User** side of the application — day-to-day
contributors submitting information, as opposed to the **Admin** side
covered in the [Admin Guide](admin/index.md). Which side is available
after logging in depends entirely on the account used: see
[Configuration](configuration.md) for how an administrator sets up
accounts and assigns each one the `admin` or `user` role.

## Logging in

The login screen is the same one everyone uses — there's no separate
"User" login page. After entering a username and password, a User
account lands on its own dashboard, distinct from the Admin dashboard
described in [Data Entry](admin/data_entry.md), listing only the record
types this instance accepts public submissions for.

```{note}
Screenshot needed: `docs/source/_static/screenshots/user-dashboard.png`
— the User dashboard after logging in, showing the record types
available for submission.
```

![User dashboard](_static/screenshots/user-dashboard.png)
*The User dashboard.*

## Submitting a form

Choosing a record type opens a form — built the same ontology-driven
way described in [Philosophy & Design](philosophy.md), but offering only
a smaller, specific set of fields chosen for public submission, not the
full set an administrator sees. Required fields and validation work
exactly as described in [Data Entry](admin/data_entry.md)'s "Required
fields and validation" section: an incomplete or invalid submission
redisplays the same form with a clear banner listing what needs fixing,
and nothing already typed is lost.

```{note}
Screenshot needed:
`docs/source/_static/screenshots/user-submission-form.png` — a User
submission form, showing its (smaller) set of fields.
```

![User submission form](_static/screenshots/user-submission-form.png)
*A User-facing submission form.*

(announcing-a-project)=
## Announcing a project application

The main thing the User side is used for is telling the administrators that
you have **applied for a project**. The project form asks for the basics:

- **Title** of the project.
- **PI** — the principal investigator. This is a lookup, not free text:
  start typing a surname and choose the person from the list that appears.
  It is **required**, and it is how the administrators know who is
  responsible for what you are announcing. More than one can be given, and a
  **co-PI** can be added the same way.
- **Call for proposal title**, and the **Application URL** — the full
  web address of the call or application page, starting `http://` or
  `https://` (required; an identifier on its own is not accepted).
- **Funding status** (usually *Proposed* at this stage) and the funding
  amounts, if you know them.
- **Comments** — a free-text box for anything the administrators should
  know that the other fields don't cover, for example that the project is
  funding your own contract, or a deadline. It is included in the email they
  receive.

You are *not* asked what **kind** of project it is, and there are no dates to
fill in: both are decided later by the administrators, who go through each
submission, classify it and complete it (see [Data
Entry](admin/data_entry.md#curating-a-project-submitted-by-a-member)). Dates only become
required once the project has been awarded.

A note on the login: the User account is a shared one set up by the
administrator, not a personal login (see [Configuration](configuration.md)),
so the system does **not** know who is filling the form in. The PI field is
how a submission says who is responsible; if you are the person it concerns
but not the PI, say so in the Comments.

## What happens after submitting

Once a submission passes validation, two things happen right away:

1. **A new record is created immediately** — a User's submission isn't
   held in some separate queue waiting for an administrator to approve
   it before it exists; it's written to the database as a real record as
   soon as it's submitted.
2. **An administrator is emailed automatically**, so someone reviews the
   new submission — the email lists exactly what was submitted and links
   directly to the new record in the Admin interface (see the "Admin
   email notifications" section of [Configuration](configuration.md) for
   how this address is set up).

The screen that appears after a successful submission confirms this and
says it's safe to close the window — there's nothing further to do.

```{note}
Screenshot needed: `docs/source/_static/screenshots/user-thank-you.png`
— the confirmation screen shown after a successful submission.
```

![Thank-you screen](_static/screenshots/user-thank-you.png)
*The confirmation screen after a successful submission.*

In short: submitting a form through the User side bootstraps a new
record and lets an administrator know there's something new to look
at — it's the starting point for getting new information into the
system, not a final, unreviewed publication of it.
