import Foundation

public struct ToolDefinition: Sendable {
    public let id: String
    public let title: String
    public let name: String
    public let symbol: String
    public let description: String

    public static let all: [String: ToolDefinition] = [
        "cropImage": ToolDefinition(
            id: "cropImage",
            title: "CROP",
            name: "Freeform Crop",
            symbol: "crop",
            description: "Freeform crop canvas to freely select and export any area as WebP, PNG, JPG, or PDF."
        ),
        "resizeImage": ToolDefinition(
            id: "resizeImage",
            title: "RESIZE",
            name: "Resize & Edit",
            symbol: "arrow.up.left.and.down.right.magnifyingglass",
            description: "Open interactive editor to scale, rotate, and customize dimensions."
        ),
        "createPDF": ToolDefinition(
            id: "createPDF",
            title: "CREATE PDF",
            name: "Create PDF",
            symbol: "doc.badge.plus",
            description: "Convert image or combine multiple images into a high-quality PDF document."
        ),
        "compress": ToolDefinition(
            id: "compress",
            title: "COMPRESS",
            name: "Compress",
            symbol: "arrow.down.right.and.arrow.up.left",
            description: "Reduce file size locally while keeping original file untouched."
        ),
        "removeMetadata": ToolDefinition(
            id: "removeMetadata",
            title: "METADATA",
            name: "Strip Metadata",
            symbol: "tag",
            description: "Strip camera, GPS, and personal metadata."
        ),
        "splitPDF": ToolDefinition(
            id: "splitPDF",
            title: "SPLIT",
            name: "Split PDF",
            symbol: "rectangle.split.2x1",
            description: "Extract individual pages to folder."
        ),
        "mergePDF": ToolDefinition(
            id: "mergePDF",
            title: "MERGE",
            name: "Merge PDFs",
            symbol: "doc.on.doc",
            description: "Combine multiple PDFs into one document."
        ),
        "organizePDF": ToolDefinition(
            id: "organizePDF",
            title: "ORGANIZE",
            name: "Organize PDF",
            symbol: "square.grid.2x2",
            description: "Rotate and reorder pages."
        ),
        "normalizeAudio": ToolDefinition(
            id: "normalizeAudio",
            title: "NORMALIZE",
            name: "Normalize",
            symbol: "waveform",
            description: "Normalize audio volume levels."
        ),
        "trimAudio": ToolDefinition(
            id: "trimAudio",
            title: "TRIM",
            name: "Trim Audio",
            symbol: "scissors",
            description: "Trim audio track duration."
        ),
        "muteVideo": ToolDefinition(
            id: "muteVideo",
            title: "MUTE",
            name: "Remove Audio",
            symbol: "speaker.slash.fill",
            description: "Strip audio track from video."
        ),
        "trimVideo": ToolDefinition(
            id: "trimVideo",
            title: "TRIM",
            name: "Trim Video",
            symbol: "scissors",
            description: "Trim video duration."
        ),
        "changeVideoSpeed": ToolDefinition(
            id: "changeVideoSpeed",
            title: "SPEED",
            name: "Speed",
            symbol: "speedometer",
            description: "Speed up video (2x) or slow down."
        ),
        "joinVideos": ToolDefinition(
            id: "joinVideos",
            title: "JOIN",
            name: "Join Videos",
            symbol: "film.stack",
            description: "Combine multiple videos into one sequential video."
        ),
        "videoSnapshots": ToolDefinition(
            id: "videoSnapshots",
            title: "SNAPSHOT",
            name: "Snapshots",
            symbol: "camera",
            description: "Extract full-resolution frame images."
        ),
        "extractArchive": ToolDefinition(
            id: "extractArchive",
            title: "EXTRACT",
            name: "Extract",
            symbol: "archivebox",
            description: "Unpack archive contents."
        )
    ]
}

public struct ActionDefinition: Sendable {
    public let id: String
    public let title: String
    public let name: String
    public let symbol: String
    public let description: String

    public static let all: [String: ActionDefinition] = [
        "airDrop": ActionDefinition(id: "airDrop", title: "AIRDROP", name: "AirDrop", symbol: "airplayaudio", description: "Share files and folders through AirDrop."),
        "float": ActionDefinition(id: "float", title: "FLOAT", name: "Float", symbol: "pin.fill", description: "Keep files in a floating shelf."),
        "copy": ActionDefinition(id: "copy", title: "COPY", name: "Copy", symbol: "doc.on.doc", description: "Copy files to the clipboard, ready to paste in Finder."),
        "move": ActionDefinition(id: "move", title: "MOVE", name: "Move", symbol: "folder", description: "Choose a destination folder and move originals there."),
        "copyPath": ActionDefinition(id: "copyPath", title: "COPY PATH", name: "Copy Path", symbol: "doc.text", description: "Copy full file paths to clipboard."),
        "openTerminal": ActionDefinition(id: "openTerminal", title: "TERMINAL", name: "Terminal", symbol: "terminal", description: "Open containing folder in Terminal.")
    ]
}
