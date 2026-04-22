combat framework

m1 combat system with combos, blocking, and server-authoritative hit validation. built for a larger project, pulled out standalone.

structure

- CombatHandler entry point, wires remotes and player lifecycle
- CombatModule hit resolution, block state, knockback
- CombatConfig tuning values
- HitboxModule overlap-based hit detection
- CombatClient input, prediction, animation, camera shake

how it works

client predicts the hit locally (animation, sound, effect) and fires a remote with a hitId, claimed origin, timestamp, and target userId. server re-resolves the target, checks distance/facing/timestamp drift/dedup, then either confirms or rejects via HitFeedback. rejected hits get cleaned up client-side.

block works as a toggle with a max-hit counter absorbs up to BlockMaxHits hits then breaks with knockback.

notes

- LinearVelocity for knockback, not the deprecated BodyVelocity
- supports R6 and R15
- no _G globals, no leftover debug prints
- assets (sounds, effects, animations) expected in ReplicatedStorage.CombatAssets
- remotes expected in ReplicatedStorage.Remotes.Combat (Punch, Block, HitFeedback)

not included

- animations, sounds, VFX
- the Fists tool
- xp / progression integration (hook in after targetHum:TakeDamage)

made by lost · roblox scripter · dm on discord for hire 


@havefaithnotfear
