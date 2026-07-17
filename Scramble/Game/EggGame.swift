import Foundation
import simd

enum EggEvent {
    case spawned(id: Int, chute: Int)
    case caught(id: Int, at: SIMD3<Double>)
    case broken(id: Int, at: SIMD3<Double>)
    case gameOver(finalScore: Int, best: Int)
}

/// Wolf-and-Eggs game logic. Eggs roll down four chutes (two per side); the
/// player's net head must be near a chute's end when the egg gets there.
/// Rolling speed and spawn rate ramp up with the score.
final class EggGame {

    struct Chute {
        let start: SIMD3<Double>
        let end: SIMD3<Double>
        var direction: SIMD3<Double> { simd_normalize(end - start) }
    }

    struct Egg {
        let id: Int
        let chute: Int
        var rollProgress = 0.0        // 0…1 along the chute
        var rollDuration: Double
        var falling = false
        var position: SIMD3<Double>
        var velocity = SIMD3<Double>.zero
    }

    enum Phase { case waiting, playing }

    /// Ends sit on the arc the net head can reach from its fixed base.
    static let chutes: [Chute] = [
        Chute(start: SIMD3(-3.0, 2.05, 0), end: SIMD3(-0.75, 1.05, 0)),   // upper left
        Chute(start: SIMD3(-3.0, 1.35, 0), end: SIMD3(-0.90, 0.62, 0)),   // lower left
        Chute(start: SIMD3(3.0, 2.05, 0), end: SIMD3(0.75, 1.05, 0)),     // upper right
        Chute(start: SIMD3(3.0, 1.35, 0), end: SIMD3(0.90, 0.62, 0)),     // lower right
    ]

    private(set) var phase: Phase = .waiting
    private(set) var score = 0
    private(set) var bestScore = 0
    private(set) var eggs: [Egg] = []

    let catchRadius = 0.45

    private var nextEggID = 0
    private var timeToNextSpawn = 0.8
    private var lastChute = -1
    /// The very first egg always comes from the upper-LEFT chute: the player's
    /// first reach toward it silently defines the heading anchor.
    private var firstSpawnEver = true

    func startPlaying() {
        guard phase == .waiting else { return }
        phase = .playing
        score = 0
        eggs = []
        timeToNextSpawn = 0.8
    }

    /// Ends the current round without scoring (e.g. mid-round recalibration).
    func abort() {
        guard phase == .playing else { return }
        bestScore = max(bestScore, score)
        phase = .waiting
        eggs = []
    }

    func update(dt: Double, netHead: SIMD3<Double>) -> [EggEvent] {
        guard phase == .playing else { return [] }
        var events: [EggEvent] = []

        timeToNextSpawn -= dt
        if timeToNextSpawn <= 0 {
            spawn(&events)
            timeToNextSpawn = max(0.9, 2.4 * pow(0.985, Double(score)))
        }

        var kept: [Egg] = []
        for var egg in eggs {
            if egg.falling {
                egg.velocity.y -= 9.81 * dt
                egg.position += egg.velocity * dt
                if egg.position.y <= 0.06 {
                    // One life: a broken egg ends the round.
                    bestScore = max(bestScore, score)
                    events.append(.broken(id: egg.id, at: egg.position))
                    events.append(.gameOver(finalScore: score, best: bestScore))
                    phase = .waiting
                    eggs = []
                    return events
                }
            } else {
                egg.rollProgress += dt / egg.rollDuration
                let chute = Self.chutes[egg.chute]
                let s = min(egg.rollProgress, 1)
                let eased = s * s * 0.6 + s * 0.4          // accelerating roll
                egg.position = chute.start + (chute.end - chute.start) * eased
                if egg.rollProgress >= 1 {
                    if simd_distance(netHead, chute.end) < catchRadius {
                        score += 1
                        events.append(.caught(id: egg.id, at: chute.end))
                        continue
                    }
                    egg.falling = true
                    let speed = simd_length(chute.end - chute.start) / egg.rollDuration * 1.4
                    egg.velocity = chute.direction * speed
                }
            }
            kept.append(egg)
        }
        eggs = kept
        return events
    }

    private func spawn(_ events: inout [EggEvent]) {
        var chute = firstSpawnEver ? 0 : Int.random(in: 0..<Self.chutes.count)
        firstSpawnEver = false
        if chute == lastChute { chute = (chute + 1) % Self.chutes.count }
        lastChute = chute
        let duration = max(1.1, 2.6 * pow(0.985, Double(score)))
        let egg = Egg(id: nextEggID, chute: chute, rollDuration: duration,
                      position: Self.chutes[chute].start)
        nextEggID += 1
        eggs.append(egg)
        events.append(.spawned(id: egg.id, chute: chute))
    }
}
