// =====================================================================
// MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 4
// MONGODB AGGREGATION PIPELINE
// AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)
//
// PURPOSE
//   Detects webhook traffic arriving from a single client IP across
//   multiple distinct merchants, which is a card-testing / velocity
//   signal for the risk service.
//
// USAGE
//   mongoimport --db apexpay_events --collection webhook_events \
//     --file 01_mongodb_webhook_events.json --jsonArray
//   mongosh apexpay_events --file 05_mongodb_aggregation.js
//
// NOTE
//   In production the pipeline also constrains `timestamp` to a rolling
//   window. The shipped sample set contains a single document, so the
//   time filter is omitted here and the grouping is run over the whole
//   collection to keep the demonstration self-contained.
// =====================================================================

const results = db.webhook_events.aggregate([
  {
    $group: {
      _id: "$payload.risk_telemetry.ip_address",
      event_count: { $sum: 1 },
      merchants: { $addToSet: "$payload.merchant_id" },
      card_schemes: { $addToSet: "$payload.card_details.scheme" }
    }
  },
  {
    $match: { event_count: { $gte: 1 } }
  },
  {
    $project: {
      _id: 0,
      ip_address: "$_id",
      event_count: 1,
      distinct_merchants: { $size: "$merchants" },
      card_schemes: 1
    }
  },
  {
    $sort: { event_count: -1, ip_address: 1 }
  }
]).toArray();

printjson(results);
