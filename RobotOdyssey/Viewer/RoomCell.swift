import SwiftUI

/// A room's thumbnail with its number below, outlined when selected.
struct RoomCell: View {
    var model: ViewerModel
    let world: World
    let room: Int

    var body: some View {
        let isCode = world.codeRooms[room] != nil
        VStack(spacing: 2) {
            RoomImage(model: model, world: world, room: room, showEmpty: model.showEmptyRooms)
                .aspectRatio(280.0 / 192.0, contentMode: .fit)
                .overlay {
                    if room == model.selectedRoom { Rectangle().stroke(Color.accentColor, lineWidth: 3) }
                }
            Text(hex(room)).font(.caption2.monospaced())
                .foregroundStyle(world.isRoomUsed(room) && !isCode ? .primary : .tertiary)
        }
        .contentShape(Rectangle())
        .help(roomTitle(room) + (isCode ? " – 6502 code" : ""))
    }
}

/// A room's thumbnail; the selected room as the running loop shows it.
/// Unused rooms are blank unless `showEmpty`, code rooms always.
struct RoomImage: View {
    var model: ViewerModel
    let world: World
    let room: Int
    let showEmpty: Bool

    var body: some View {
        if world.codeRooms[room] != nil {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "curlybraces").foregroundStyle(.orange) }
        } else if showEmpty || world.isRoomUsed(room),
                  let image = (room == model.selectedRoom ? model.liveThumbnail(world: world, room: room) : nil)
                      ?? model.thumbnail(room: room) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable()
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}
