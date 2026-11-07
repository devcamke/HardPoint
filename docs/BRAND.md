# HardPoint look and layout

The back office is arranged in a few areas named for the job to be done, in petrol teal. Lists and forms follow Odoo's
layout, so they look familiar to anyone who has used a business suite. Why it's arranged this way: [SIMPLIFY.md](SIMPLIFY.md).

## Layout

- **Top bar:** the logo (to Home), then six areas: **Home, Sell, Customers, Stock, Buy, Reports**, limited to what
  the person's role uses. On the right: **Search** (Ctrl K), **Open till** for those who sell, the ⚙ for Settings,
  and the user menu (profile, switch user, help, sign out) under the initials. The areas and their menus are defined
  in `app/helpers/navigation_helper.rb`; pages reached from inside an area are listed as its `prefixes`, so the area
  stays highlighted.
- **Area menu:** a white bar under the top bar with the current area's pages; the current one is underlined.
  Each page has one home: never list a page in two menus. Settings (catalogue lists, staff, activity) is the place
  for things set up once.
- **Optional features:** anything only some shops use is switched on in Settings › Features
  (`Account::Features`). Guard its menu entry, Settings tile, Home row and form fields with `feature?(:key)`.
- **Home:** owners and managers get today's numbers and **Needs you today** (`HomeHelper#home_tasks`): one row per
  thing to act on, with the button that does it. Every number on Home should lead to an action. Staff without
  reports get one big **Start selling** button.
- **Search** (`SearchesController`, `command_palette_controller.js`): products, customers, suppliers, document
  numbers and pages. When a page is renamed or moved, add its old name to its keywords in `SearchHelper`.
- **Forms:** the fields people fill in nine times out of ten up front; the rest under **More options** with a
  one-line summary of the defaults it's using.
- **Control panel on list pages** (`app/views/shared/_control_panel.html.erb`): the **New** button and title on
  the left with a ⚙ menu for other actions, the search bar in the middle, and the pager (`1-50 ‹ ›`) on the right.
  Active filters show in the search bar as facets ("Status: Open orders ×"); the ▾ opens the filters. Enter
  searches, and Backspace in an empty box removes the last facet. Filters are declared per page with
  `search_filter` (`app/helpers/control_panel_helper.rb`).
- **Group By** is on Products (category, brand), Purchase orders (supplier, status) and Orders & quotes
  (status, customer), and on the reports. Each group shows its count and totals over the whole list (totals in
  each currency for suppliers who invoice in dollars) and opens to load its records. It's left off the other
  lists on purpose: the reports already give those breakdowns. See `ListGrouping` and `shared/_list_groups`.
- **Page titles:** one line, with the parent page as a breadcrumb: `Products / New product`.
- **Lists** are flat white tables with a grey header line; **forms** use underlined fields.
- **Settings** are grouped into sections, with a section index on the left.

## Colours

| Token | Hex | Use |
|---|---|---|
| `primary-500` | `#0F5E6E` | Top bar, primary buttons, selected states, charts |
| `accent-600` | `#0D505E` | Links |
| `gray-*` | Tailwind greys | Text (`gray-800`), muted text (`gray-500`), borders (`gray-200`), page (`gray-50`) |
| `amber-*` | Tailwind amber | Warnings: low stock, payment due, offline, impersonation |
| `red-*`, `green-*` | Tailwind | Errors and destructive actions; success notices |

White text on `primary-500` is 7.4:1, `accent-600` on white is 9.0:1 and `gray-500` on the page is 4.6:1, all above WCAG AA.

## Rules

- One primary (petrol) button per screen, for the main action. Everything else is `btn-secondary`.
- Amber means "needs attention", never decoration.

## Logo

A hex nut next to the wordmark **HardPoint**, rendered by `app/views/shared/_logo.html.erb`. The app icon
(`public/icon.svg`, `icon.png`) is a white nut on a petrol rounded square.

## Components

Utilities in `app/assets/tailwind/application.css`: `btn-primary`, `btn-secondary`, `btn-danger`, `input`, `label`,
`field`, `card`, `link`, `hint`, `badge`, and the `.table` component.
