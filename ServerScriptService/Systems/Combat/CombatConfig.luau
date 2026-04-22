local CombatConfig = {}

-- { constants }
CombatConfig.Damage = 10
CombatConfig.AttackCooldown = 0.4
CombatConfig.ComboResetTime = 1.2
CombatConfig.MaxCombo = 3

CombatConfig.Knockback = 50
CombatConfig.KnockbackDuration = 0.1

CombatConfig.BaseWalkSpeed = 16
CombatConfig.AfterPunchSpeed = 11
CombatConfig.PunchSpeedRecover = 0.5

CombatConfig.BlockMinDuration = 0.15
CombatConfig.BlockToggleCooldown = 0.1
CombatConfig.BlockMaxHits = 3
CombatConfig.BlockBreakKnockback = 35

CombatConfig.HitboxSize = Vector3.new(6, 5, 5)
CombatConfig.HitboxOffset = Vector3.new(0, 0, -3)

CombatConfig.HitAngle = -0.2
CombatConfig.PositionTolerance = 8
CombatConfig.MaxHitRange = 10
CombatConfig.MaxTimestampDrift = 1.0

CombatConfig.RemoteCooldown = 0.05
CombatConfig.HitClearDelay = 0.4

return CombatConfig
