window.WYRD_DATA = {
  // One entry per A/B match: add a line after every match (see CLAUDE.md).
  matches: [
    { net: "wyrd-i (wdl 0.5, 20 rounds)", round: 1, vs: "material", elo: -148, err: 24, games: 600, accepted: false, note: "rejected" },
    { net: "wyrd-i (wdl 0.0, 200 rounds)", round: 1, vs: "material", elo: 14, err: 20, games: 600, accepted: false, note: "teacher for round 2, not significant" },
    { net: "r2b (wdl 0.3)", round: 2, vs: "material", elo: -35, err: 19, games: 600, accepted: false, note: "rejected" },
    { net: "wyrd-ii (wdl 0.0)", round: 2, vs: "material", elo: 115, err: 23, games: 600, accepted: true, note: "accepted" },
    { net: "wyrd-ii (wdl 0.0)", round: 2, vs: "wyrd-i", elo: 117, err: 22, games: 600, accepted: true, note: "accepted" }
  ],
  // Training loss per round, one series per run (name -> [[round, loss], ...]).
  loss: {
    "wyrd-ii run (data r2, wdl 0.0)": [
[1,0.011651],[2,0.001454],[3,0.001307],[4,0.001239],[5,0.001194],[10,0.001072],[15,0.001013],[20,0.000977],[25,0.000952],[30,0.000935],[35,0.000921],[40,0.000910],[45,0.000900],[50,0.000895],[55,0.000886],[60,0.000882],[65,0.000877],[70,0.000876],[75,0.000871],[80,0.000868],[85,0.000865],[90,0.000863],[95,0.000860],[100,0.000856],[105,0.000857],[110,0.000852],[115,0.000850],[120,0.000851],[125,0.000849],[130,0.000847],[135,0.000845],[140,0.000844],[145,0.000843],[150,0.000843],[155,0.000825],[160,0.000825],[165,0.000827],[170,0.000824],[175,0.000824],[180,0.000826],[185,0.000825],[190,0.000824],[195,0.000824],[200,0.000823]
    ]
  }
};
