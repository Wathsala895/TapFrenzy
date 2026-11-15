import SwiftUI
import UIKit
internal import Combine

// MARK: - Step 5: Game phases
enum GamePhase {
    case idle, playing, over
}

struct ContentView: View {

    // MARK: Core state (Steps 3–6)
    @State private var score = 0
    @State private var timeRemaining = 10
    @State private var phase: GamePhase = .idle
    @AppStorage("highScore") private var highScore = 0      // Step 6: persisted
    @State private var isNewBest = false

    // Stretch: round length picker
    @State private var roundLength = 10
    private let roundOptions = [5, 10, 20]

    // C1: Combo
    @State private var lastTapTime: Date?
    @State private var multiplier = 1

    // C2: Trap colour
    @State private var isTrap = false
    @State private var trapTicksLeft = 0

    // C3: Moving target
    @State private var targetOffset: CGSize = .zero
    @State private var moveTicks = 0

    // C4: Shrinking button
    @State private var tapCount = 0

    // C5: Bonus burst
    @State private var showBonus = false
    @State private var bonusTicksLeft = 0
    @State private var bonusUnit = CGPoint(x: 0.5, y: 0.2)

    // Stretch: animated score
    @State private var scoreBump = false

    // Step 4: countdown timer (1s), plus a fast 0.1s tick for the challenges
    private let countdown = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let fastTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // MARK: Derived values
    private var displayTime: Int { phase == .idle ? roundLength : timeRemaining }

    // Stretch: timer colour shift (green → amber → red)
    private var timerColor: Color {
        let fraction = Double(displayTime) / Double(roundLength)
        return fraction > 0.5 ? .green : (fraction > 0.25 ? .orange : .red)
    }

    private var buttonScale: CGFloat {
        max(0.45, 1 - CGFloat(tapCount) * 0.012)   // C4
    }

    // MARK: Body
    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()

                switch phase {
                case .idle, .playing:
                    if landscape {
                        HStack(spacing: 24) {
                            infoPanel
                            tapArea
                        }
                        .padding()
                    } else {
                        VStack(spacing: 20) {
                            infoPanel
                            Spacer(minLength: 0)
                            tapArea
                            Spacer(minLength: 0)
                        }
                        .padding()
                    }
                case .over:
                    gameOverView
                }

                // C5: Bonus burst button
                if phase == .playing && showBonus {
                    Button(action: bonusTapped) {
                        Text("+5")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color.yellow))
                            .shadow(color: .yellow.opacity(0.7), radius: 10)
                    }
                    .buttonStyle(.plain)
                    .position(x: bonusUnit.x * geo.size.width,
                              y: bonusUnit.y * geo.size.height)
                    .transition(.scale)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(countdown) { _ in tickCountdown() }
        .onReceive(fastTick) { _ in tickFast() }
    }

    // MARK: Sub-views
    private var infoPanel: some View {
        VStack(spacing: 10) {
            Text("Tap Frenzy")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("SCORE")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.gray)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(score)")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
                    .minimumScaleFactor(0.5)
                    .scaleEffect(scoreBump ? 1.2 : 1.0)          // Stretch: animated score
                    .contentTransition(.numericText())

                // C1: combo indicator
                if multiplier > 1 && phase == .playing {
                    Text("x\(multiplier)!")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.yellow)
                        .transition(.scale)
                }
            }

            // Timer label + bar
            Text(phase == .idle ? "tap to start" : "\(displayTime)s")
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(phase == .idle ? .gray : timerColor)

            ProgressView(value: Double(displayTime), total: Double(roundLength))
                .tint(timerColor)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.horizontal)
                .animation(.linear(duration: 1), value: displayTime)

            // Stretch: round length picker (only before a round)
            if phase == .idle {
                Picker("Round length", selection: $roundLength) {
                    ForEach(roundOptions, id: \.self) { Text("\($0)s").tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
        }
    }

    private var tapArea: some View {
        Button(action: tapPressed) {
            Text(isTrap ? "NO!" : "TAP")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 200, height: 200)
                .background(Circle().fill(isTrap ? Color.red : Color.green))   // C2
                .shadow(color: (isTrap ? Color.red : Color.green).opacity(0.5), radius: 20)
        }
        .buttonStyle(.plain)
        .scaleEffect(buttonScale)                                              // C4
        .offset(targetOffset)                                                  // C3
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: buttonScale)
        .frame(width: 320, height: 320)   // fixed play area so movement doesn't shift layout
    }

    private var gameOverView: some View {
        VStack(spacing: 18) {
            Text("TIME'S UP")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(.gray)

            Text("\(score)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundColor(.green)

            Text("Final score")
                .foregroundColor(.gray)

            Text("Best: \(highScore)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(.white)

            if isNewBest {
                Text("🏆 New high score!")
                    .font(.headline)
                    .foregroundColor(.yellow)
            }

            Button(action: resetToIdle) {
                Text("Play Again")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.green))
            }
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: Game logic
    private func startGame() {
        score = 0
        timeRemaining = roundLength
        tapCount = 0
        multiplier = 1
        lastTapTime = nil
        isTrap = false
        trapTicksLeft = 0
        showBonus = false
        targetOffset = .zero
        isNewBest = false
        phase = .playing
    }

    private func resetToIdle() {
        score = 0
        tapCount = 0
        multiplier = 1
        targetOffset = .zero
        phase = .idle
    }

    private func endGame() {
        phase = .over
        isTrap = false
        showBonus = false
        if score > highScore {          // Step 6
            highScore = score
            isNewBest = true
        }
    }

    private func tapPressed() {
        if phase == .idle { startGame() }          // first tap starts the timer
        guard phase == .playing else { return }

        tapCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()   // Stretch: haptics

        if isTrap {
            // C2: tapping during a trap costs a point
            score = max(0, score - 1)
            multiplier = 1
            lastTapTime = nil
        } else {
            // C1: combo — taps within 300ms build a multiplier up to x3
            let now = Date()
            if let last = lastTapTime, now.timeIntervalSince(last) <= 0.3 {
                multiplier = min(multiplier + 1, 3)
            } else {
                multiplier = 1
            }
            lastTapTime = now
            score += multiplier
        }
        bumpScore()
    }

    private func bonusTapped() {
        guard phase == .playing else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        score += 5
        withAnimation { showBonus = false }
        bumpScore()
    }

    private func bumpScore() {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { scoreBump = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { scoreBump = false }
        }
    }

    // Step 4: 1-second countdown
    private func tickCountdown() {
        guard phase == .playing else { return }
        if timeRemaining > 0 { timeRemaining -= 1 }
        if timeRemaining == 0 { endGame() }
    }

    // 0.1s tick driving the challenges
    private func tickFast() {
        guard phase == .playing else { return }

        // C1: combo expires if you stop tapping fast
        if let last = lastTapTime, Date().timeIntervalSince(last) > 0.3, multiplier != 1 {
            withAnimation { multiplier = 1 }
        }

        // C2: trap colour — random 0.5s red phases
        if isTrap {
            trapTicksLeft -= 1
            if trapTicksLeft <= 0 { isTrap = false }
        } else if Int.random(in: 0..<100) < 4 {
            isTrap = true
            trapTicksLeft = 5
        }

        // C3: moving target — jump every ~1.5s
        moveTicks += 1
        if moveTicks >= 15 {
            moveTicks = 0
            withAnimation(.easeInOut(duration: 0.35)) {
                targetOffset = CGSize(width: CGFloat.random(in: -60...60),
                                      height: CGFloat.random(in: -50...50))
            }
        }

        // C5: bonus burst — random gold +5 for ~1.5s
        if showBonus {
            bonusTicksLeft -= 1
            if bonusTicksLeft <= 0 { withAnimation { showBonus = false } }
        } else if Int.random(in: 0..<100) < 3 {
            bonusUnit = CGPoint(x: CGFloat.random(in: 0.15...0.85),
                                y: CGFloat.random(in: 0.12...0.88))
            bonusTicksLeft = 15
            withAnimation { showBonus = true }
        }
    }
}

#Preview {
    ContentView()
}
