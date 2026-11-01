# HardPoint look and layout

The back office follows Odoo's layout and colours, so it looks familiar to anyone who has used a business suite.

## Layout

- **Home menu:** the grid button at the top left opens a full-screen menu of apps (Dashboard, Point of Sale,
  Sales, Tool Hire, Products, Inventory, Purchase, Reports, Employees, Settings, Help). Staff who can't see the
  dashboard land on the same tiles. The apps and their menus are defined in `app/helpers/navigation_helper.rb`.
- **Top bar:** the current app's name followed by that app's menu. The user menu (profile, switch user, help,
  sign out) is under the initials at the top right.
- **Control panel on list pages** (`app/views/shared/_control_panel.html.erb`): the **New** button and title on
  the left with a ⚙ menu for other actions, the search bar in the middle, and the pager (`1-50 ‹ ›`) on the right.
  Active filters show in the search bar as facets ("Status: Open orders ×"); the ▾ opens the filters. Enter
  searches, and Backspace in an empty box removes the last facet. Filters are declared per page with
  `search_filter` (`app/helpers/control_panel_helper.rb`).
- **Page titles:** one line, with the parent page as a breadcrumb: `Products / New product`.
- **Lists** are flat white tables with a grey header line; **forms** use underlined fields.
- **Settings** are grouped into sections, with a section index on the left.

## Colours

| Token | Hex | Use |
|---|---|---|
| `primary-500` | `#714B67` | Top bar, primary buttons, selected states, charts |
| `accent-600` | `#017E84` | Links |
| `gray-*` | Tailwind greys | Text (`gray-800`), muted text (`gray-500`), borders (`gray-200`), page (`gray-50`) |
| `amber-*` | Tailwind amber | Warnings: low stock, payment due, offline, impersonation |
| `red-*`, `green-*` | Tailwind | Errors and destructive actions; success notices |

White text on `primary-500` is 7.2:1, `accent-600` on white is 4.9:1 and `gray-500` on the page is 4.6:1, all above WCAG AA.

## Rules

- One primary (purple) button per screen, for the main action. Everything else is `btn-secondary`.
- Amber means "needs attention", never decoration.

## Logo

A hex nut next to the wordmark **HardPoint**, rendered by `app/views/shared/_logo.html.erb`. The app icon
(`public/icon.svg`, `icon.png`) is a white nut on a purple rounded square.

## Components

Utilities in `app/assets/tailwind/application.css`: `btn-primary`, `btn-secondary`, `btn-danger`, `input`, `label`,
`field`, `card`, `link`, `hint`, `badge`, and the `.table` component.
