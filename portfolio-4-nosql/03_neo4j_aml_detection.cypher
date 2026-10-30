// MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 4
// NEO4J GRAPH MODEL & CYCLIC MONEY LAUNDERING TRAVERSAL
// AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)

// Reset the demonstration graph so the script is safe to re-run: without this
// a second execution would accumulate duplicate Account and Device nodes from
// the previous run and inflate the cycle-detection result.
MATCH (n) DETACH DELETE n;

// Steps 1 and 2 run as ONE statement. Cypher variables are scoped to a single
// statement, so a later `CREATE (a)-[...]->(b)` that relies on variables bound
// in an earlier statement fails with: Variable `a` not defined.
CREATE (a:Account {account_number: "0123456789", holder: "Mule Alpha", kyc_tier: 1}),
       (b:Account {account_number: "0449911223", holder: "Mule Beta",  kyc_tier: 1}),
       (c:Account {account_number: "0554433221", holder: "Mule Gamma", kyc_tier: 2}),
       (d:Device  {fingerprint: "dev_982bfa11", os: "Android 14"}),
       (a)-[:TRANSFERRED_TO {amount: 250000.00, timestamp: datetime('2026-10-15T10:00:00Z')}]->(b),
       (b)-[:TRANSFERRED_TO {amount: 240000.00, timestamp: datetime('2026-10-15T14:30:00Z')}]->(c),
       (c)-[:TRANSFERRED_TO {amount: 230000.00, timestamp: datetime('2026-10-16T09:15:00Z')}]->(a),
       (a)-[:OPERATES_ON]->(d),
       (b)-[:OPERATES_ON]->(d);

// Step 3: Cypher Query — Detect 3-Hop Circular Smurfing Ring within 48 Hours
MATCH path = (muleA:Account)-[t1:TRANSFERRED_TO]->(muleB:Account)
                            -[t2:TRANSFERRED_TO]->(muleC:Account)
                            -[t3:TRANSFERRED_TO]->(muleA:Account)
WHERE muleA <> muleB AND muleB <> muleC AND muleA <> muleC
  AND t1.amount >= 200000.00
  AND t2.amount >= 190000.00
  AND t3.amount >= 180000.00
  AND duration.inDays(t1.timestamp, t3.timestamp).days <= 2
RETURN 
    muleA.account_number AS First_Mule,
    muleB.account_number AS Second_Mule,
    muleC.account_number AS Third_Mule,
    t1.amount AS Hop1_Transfer,
    t2.amount AS Hop2_Transfer,
    t3.amount AS Hop3_Transfer,
    (t1.amount - t3.amount) AS Retained_Laundering_Cut;
