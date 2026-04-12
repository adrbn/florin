export interface TutorialStep {
  selector: string
  title: string
  description: string
}

export const DEFAULT_TUTORIAL_STEPS: TutorialStep[] = [
  {
    selector: '[data-tutorial=net-worth]',
    title: 'Net Worth',
    description: 'This is your net worth — the total value of all your accounts',
  },
  {
    selector: '[data-tutorial=burn-rate]',
    title: 'Burn Rate',
    description: 'Your burn rate shows how much you spend per month',
  },
  {
    selector: '[data-tutorial=add-transaction]',
    title: 'Add a Transaction',
    description: 'Click here to add a transaction manually',
  },
  {
    selector: '[data-tutorial=sidebar]',
    title: 'Sidebar Navigation',
    description: 'The sidebar lets you navigate between sections',
  },
  {
    selector: '[data-tutorial=tray]',
    title: 'Menu Bar Access',
    description: 'Use the menu bar icon for quick access anytime',
  },
]
