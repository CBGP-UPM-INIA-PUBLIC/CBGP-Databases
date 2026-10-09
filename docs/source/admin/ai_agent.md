# Asking questions through an AI agent

The application can be questioned by an AI agent, in plain language, instead of
through the search pages: "how many members are active?", "who is funded by this
project?", "show me a timeline of this person's funding". The agent only *reads*
the same records the search pages show. It cannot add, change or delete anything.

This is built on the Model Context Protocol (MCP), so any agent that speaks it
can be connected. Nothing in it is specific to this institute: what the agent
knows about the data comes from the ontology, exactly like the rest of the
application.

## Connecting an agent

The address is the application's own address followed by `/mcp`, for example
`https://staff.admin.cbgp.upm.es/mcp`. It accepts `POST` requests only, and every
request must carry the `Authorization: Bearer <token>` header, with the token set
as `MCP_TOKEN` (see [Configuration](../configuration.md#ai-agent-access-mcp)).
Until `MCP_TOKEN` is set the endpoint is switched off.

For an agent that is configured with a file, the entry looks like this (this
example is for Hermes; other agents use the same two pieces of information):

```yaml
mcp_servers:
  cbgp:
    url: "https://staff.admin.cbgp.upm.es/mcp"
    headers:
      Authorization: "Bearer ${CBGP_MCP_TOKEN}"
```

Keep the name short. Agents usually put it in front of every tool's name, and some
model providers limit how long a tool name may be.

To check the connection from the server, before involving the agent:

```bash
curl -s -X POST https://your-host/mcp \
  -H "Authorization: Bearer $MCP_TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

A list of tools means it works. A `401` means the token is wrong, and a message
saying MCP is disabled means `MCP_TOKEN` is not set in the running container.

## What the agent can do

| Tool | What it is for |
|---|---|
| `describe_form` | What data exists: the forms, and the fields of each one |
| `search_records` | Find records by text, exact value or date; also counts ("how many") |
| `get_record` | One record in full, with cross-references shown as names |
| `linked_records` | Follow relationships: a person's projects, commitments and publications; a project's people |
| `record_history` | How one record changed over time, field by field |
| `render_timeline` | Draw a timeline of dated facts the agent gathered |

The agent is told to use these before searching the web for anything about the
institute's own people, projects, publications or funding, and to say which source
each figure came from. It works from what is in the database: if the records are
incomplete, so is the answer, and a good agent says so.

Only the staff-facing forms are offered. Forms that members use to submit
information are not, because nobody queries them.

## Describing your data for the agent

An agent chooses its tools by reading short descriptions, so it needs to know what
the data *is*, and which everyday words mean which form (an agent asked about
"employees" has to work out that they are in the Member form). That text is written
in the ontology, in the same place and the same way as the forms' names, in **both
languages**:

- one `rdfs:comment` on the `cbgp:forms` class says what the whole dataset is;
- one `rdfs:comment` on each form says what its records are.

```xml
<owl:Class rdf:about="https://w3id.org/CBGP-App#member">
    <rdfs:subClassOf rdf:resource="https://w3id.org/CBGP-App#forms"/>
    <rdfs:comment xml:lang="en">People who work or study at the institute: employees,
      staff, researchers, students and visitors, one record per person. The status field
      says whether a person is currently Active, Inactive or Historical; the current staff
      are those with status Active.</rdfs:comment>
    <rdfs:comment xml:lang="es">Personas que trabajan o estudian en el instituto: ...</rdfs:comment>
    <rdfs:label xml:lang="en">Member</rdfs:label>
    ...
```

Write the **first sentence** so that it stands alone: it is the only part shown in the
agent's one-line list of forms. Say what the records are and use the words people
use for them. Put the detail in the sentences after it, and the agent sees those
when it asks about that form. If something has a precise definition (such as "current
staff"), state it here: the agent will not guess it.

`check_ontology.rb` warns about any form, or the dataset itself, that has no
description in a language, so a form added later cannot go without one. A change
shows up for the agent after `/cbgp/refresh`, with no restart.

## Timelines and saving the picture

When asked to show something over time, the agent draws a timeline: bars for
things with a start and an end, a diamond for a single date, a bar that runs on to
today for something still going, and a dashed line marking today. Rows are grouped
into labelled bands, and hovering over a row shows its dates.

The picture can be saved from the timeline itself with **Download SVG** (a vector
file that opens in any drawing program or slide deck) and **Download PNG** (an
ordinary image). The PNG link appears only where the page is allowed to run its own
small script: in a saved copy of the page, or one opened on its own, but not inside
a chat window that blocks scripts. If you want the agent to hand over a PNG as an
attachment instead, ask it for "an image", and it will request one.

Making a PNG on the server needs the `rsvg-convert` program and a font. The
supplied Docker image includes both (`librsvg2-bin` and `fonts-dejavu-core`); on a
server without them an attachment request quietly falls back to the timeline page.

## Languages

Questions can be asked in English or Spanish. A value can be named in either: a
category called "Catedrático" and one called "Full professor" are the same value to
the agent. Dates can be written as `today` or `hoy`.

## Good to know

- The agent is a language model: it can misread a question. Counts and lists come
  from the database, but which records it decides to count is its own judgement,
  which is why the descriptions above state definitions such as "current staff".
- The application does not store what an agent asks. Its log records only which
  tool ran and how long it took (and, if something breaks inside the server, the
  error itself), never the question or the answer, since both can contain personal
  data. The agent program may keep its own conversation history; that is outside this
  application.
- The same records are reachable through the search pages, so the agent shows nothing
  that a logged-in administrator cannot already see.
