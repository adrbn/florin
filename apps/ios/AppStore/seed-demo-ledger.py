"""A fictional ledger for the App Store screenshots. No real person's money."""
import sqlite3, uuid, random, datetime as dt, sys

db = sys.argv[1]
con = sqlite3.connect(db)
con.execute("PRAGMA foreign_keys = OFF")
cur = con.cursor()

cats = {n: i for i, n, *_ in cur.execute(
    "SELECT c.id, c.name FROM categories c").fetchall()} if False else {}
for cid, name in cur.execute("SELECT id, name FROM categories").fetchall():
    cats[name] = cid

today = dt.date.today()
def iso(d): return d.strftime("%Y-%m-%dT00:00:00Z")
uid = lambda: str(uuid.uuid4())

ccp, livret, pea, pret = uid(), uid(), uid(), uid()
cur.executemany(
    """INSERT INTO accounts (id,name,kind,institution,currency,current_balance,display_order,
       loan_original_principal,loan_interest_rate,loan_start_date,loan_term_months,loan_monthly_payment)
       VALUES (?,?,?,?,'EUR',?,?,?,?,?,?,?)""",
    [
        (ccp, "Compte courant", "checking", "Banque", 2418.63, 0, None, None, None, None, None),
        (livret, "Livret A", "savings", "Banque", 7650.00, 1, None, None, None, None, None),
        (pea, "PEA", "broker_portfolio", "Courtier", 11240.75, 2, None, None, None, None, None),
        (pret, "Prêt étudiant", "loan", "Banque", -6420.18, 3, 12000, 0.031, "2022-09-30", 96, 141.20),
    ],
)

rows = []
def tx(account, day, amount, payee, cat=None, review=0, pair=None):
    rows.append((uid(), account, iso(day), amount, payee, payee.lower(),
                 cats.get(cat), "manual", "cleared", review, pair))

random.seed(11)
courses = ["MONOPRIX", "CARREFOUR MARKET", "LA BOULANGERIE", "PRIMEURS DU MARCHÉ", "BIOCOOP"]
sorties = ["LE PETIT COMPTOIR", "CAFÉ DES ARTS", "CINÉMA LE VOX", "PIZZERIA NAPOLI"]
transports = ["SNCF CONNECT", "NAVIGO", "TOTALENERGIES", "VÉLIB"]

for back in range(0, 14):
    first = (today.replace(day=1) - dt.timedelta(days=1)).replace(day=1) if back else today.replace(day=1)
    month = today.replace(day=1)
    for _ in range(back):
        month = (month - dt.timedelta(days=1)).replace(day=1)
    last_day = ((month.replace(day=28) + dt.timedelta(days=4)).replace(day=1) - dt.timedelta(days=1)).day
    payday = min(27, last_day)

    if back > 0 or today.day >= payday:
        tx(ccp, month.replace(day=payday), 2740.00 + (13 - back) * 12, "VIREMENT SALAIRE", "Salaires")
    tx(ccp, month.replace(day=min(3, last_day)), -880.00, "LOYER RÉSIDENCE", "Loyer")
    tx(ccp, month.replace(day=min(5, last_day)), -34.90, "ABONNEMENT MOBILE", "Abonnements")
    tx(ccp, month.replace(day=min(5, last_day)), -12.99, "STREAMING", "Abonnements")
    tx(ccp, month.replace(day=min(8, last_day)), -41.20, "ASSURANCE HABITATION", "Assurances")
    tx(ccp, month.replace(day=min(15, last_day)), -300.00, "VIREMENT ÉPARGNE", "Épargne")
    tx(ccp, month.replace(day=last_day), -141.20, "PRÉLÈVEMENT PRÊT ÉTUDIANT", "Épargne")

    for _ in range(random.randint(7, 10)):
        d = month.replace(day=random.randint(1, min(last_day, today.day if back == 0 else last_day)))
        tx(ccp, d, -round(random.uniform(9, 68), 2), random.choice(courses), "Courses")
    for _ in range(random.randint(3, 6)):
        d = month.replace(day=random.randint(1, min(last_day, today.day if back == 0 else last_day)))
        tx(ccp, d, -round(random.uniform(11, 46), 2), random.choice(sorties), "Sorties & Restos")
    for _ in range(random.randint(2, 4)):
        d = month.replace(day=random.randint(1, min(last_day, today.day if back == 0 else last_day)))
        tx(ccp, d, -round(random.uniform(4, 58), 2), random.choice(transports), "Transports")

# Two waiting to be looked at, so the queue is not empty in the screenshot.
tx(ccp, today - dt.timedelta(days=1), -23.40, "FNAC", None, review=1)
tx(ccp, today - dt.timedelta(days=2), -64.00, "DÉCATHLON", None, review=1)

cur.executemany(
    """INSERT INTO transactions
       (id,account_id,occurred_at,amount,payee,normalized_payee,category_id,source,status,needs_review,transfer_pair_id)
       VALUES (?,?,?,?,?,?,?,?,?,?,?)""", rows)

plan = {"Loyer": 880, "Abonnements": 50, "Assurances": 45, "Courses": 400,
        "Transports": 90, "Sorties & Restos": 180, "Épargne": 450, "Vêtements": 60,
        "Voyages": 150, "Cadeaux": 40}
cur.executemany(
    "INSERT INTO monthly_budgets (id,year,month,category_id,assigned) VALUES (?,?,?,?,?)",
    [(uid(), today.year, today.month, cats[n], v) for n, v in plan.items()],
)

cur.executemany(
    """INSERT INTO holdings (id,account_id,label,quote_symbol,quantity,cost_basis,last_price,currency)
       VALUES (?,?,?,?,?,?,?,'EUR')""",
    [
        (uid(), pea, "MSCI World", "CW8", 32, 8588.80, 312.55),
        (uid(), pea, "S&P 500", "ESE", 9, 1063.80, 134.80),
    ],
)

con.commit()
print("accounts", cur.execute("SELECT count(*) FROM accounts").fetchone()[0],
      "tx", cur.execute("SELECT count(*) FROM transactions").fetchone()[0])
con.close()
