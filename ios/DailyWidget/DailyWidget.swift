import WidgetKit
import SwiftUI

// Shows today's daily puzzle picture. Data comes straight from the public
// Appwrite catalogue (rows are world-readable), so no app group is needed.
struct DailyEntry: TimelineEntry {
    let date: Date
    let title: String
    let puzzleId: String
    let image: UIImage?
}

struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), title: "Today's puzzle", puzzleId: "", image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        fetch { completion($0) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        fetch { entry in
            // Refresh shortly after local midnight, or in 6 hours if the fetch failed.
            let cal = Calendar.current
            let nextMidnight = cal.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(6 * 3600)
            let refresh = entry.image == nil ? Date().addingTimeInterval(6 * 3600) : nextMidnight
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func fetch(_ done: @escaping (DailyEntry) -> Void) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let id = "daily-" + fmt.string(from: Date())
        var req = URLRequest(url: URL(string: "https://fra.cloud.appwrite.io/v1/tablesdb/cjw/tables/puzzles/rows/\(id)")!)
        req.setValue("6acb4de5003e38d5ebd9", forHTTPHeaderField: "X-Appwrite-Project")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["imageUrl"] as? String,
                  let url = URL(string: urlString) else {
                done(DailyEntry(date: Date(), title: "Today's puzzle", puzzleId: id, image: nil))
                return
            }
            let title = (json["title"] as? String) ?? "Today's puzzle"
            URLSession.shared.dataTask(with: url) { imgData, _, _ in
                let image = imgData.flatMap { UIImage(data: $0) }.map { downscale($0, maxSide: 900) }
                done(DailyEntry(date: Date(), title: title, puzzleId: id, image: image))
            }.resume()
        }.resume()
    }
}

private func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    if scale >= 1 { return image }
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
}

struct DailyWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DailyEntry

    private var titleSize: CGFloat {
        switch family {
        case .systemSmall: return 15
        case .systemMedium: return 18
        default: return 22
        }
    }

    private var titleLines: Int {
        family == .systemMedium ? 1 : 2
    }

    var body: some View {
        // Only the text is view content, so it receives the standard widget
        // margins on every family; the photo bleeds edge to edge as the
        // container background.
        VStack(alignment: .leading, spacing: 2) {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.75))
            Text(entry.title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.85)
            if family != .systemSmall {
                Text("Tap to play")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .widgetURL(URL(string: "cardjigsaw://play/\(entry.puzzleId)"))
        .containerBackground(for: .widget) {
            ZStack {
                if let img = entry.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(red: 0.09, green: 0.09, blue: 0.11)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.4))
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .init(x: 0.5, y: 0.35),
                    endPoint: .bottom
                )
            }
        }
    }
}

@main
struct DailyWidget: Widget {
    let kind = "DailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyProvider()) { entry in
            DailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily puzzle")
        .description("Today's picture, ready to play.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
