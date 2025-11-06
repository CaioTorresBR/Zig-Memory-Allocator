const std = @import("std");

const Header = struct {
    len: usize,
    free: bool,
};

const header_alignment = std.mem.Alignment.of(Header);

const AllocateurRecycle = struct {
    buffer: []u8,
    next: usize,

    /// Crée un allocateur à recyclage gérant la zone de mémoire délimitée
    /// par la tranche `buffer`.
    fn init(buffer: []u8) AllocateurRecycle {
        return .{
            .buffer = buffer,
            .next = 0,
        };
    }

    /// Retourne l’interface générique d’allocateur correspondant à
    /// cet allocateur à recyclage.
    fn allocator(self: *AllocateurRecycle) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .free = free,
                .resize = std.mem.Allocator.noResize,
                .remap = std.mem.Allocator.noRemap,
            },
        };
    }

    /// Tente d’allouer un bloc de mémoire de `len` octets dont l’adresse
    /// est alignée suivant `alignment`. Retourne un pointeur vers le début
    /// du bloc alloué, ou `null` pour indiquer un échec d’allocation.
    fn alloc(
        ctx: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        // le paramètre `return_address` peut être ignoré dans ce contexte
        _ = return_address;

        // récupère un pointeur vers l’instance de notre allocateur
        const self: *AllocateurRecycle = @ptrCast(@alignCast(ctx));

        // par la suite, `self.buffer` et `self.next` désignent les deux
        // champs de l’allocateur

        // (SUPPRIMER LES LIGNES SUIVANTES ET COMPLÉTER!)
        _ = self;
        _ = len;
        _ = alignment;
        return null;
    }

    /// Récupère l’en-tête associé à l’allocation débutant à l’adresse `ptr`.
    fn getHeader(ptr: [*]u8) *Header {
        // (SUPPRIMER LES LIGNES SUIVANTES ET COMPLÉTER!)
        return @ptrCast(@alignCast(ptr));
    }

    /// Marque un bloc de mémoire précédemment alloué comme étant libre.
    fn free(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        // les paramètres `ctx`, `alignment` et `return_address`
        // peuvent être ignorés dans ce contexte
        _ = ctx;
        _ = alignment;
        _ = return_address;

        // (SUPPRIMER LES LIGNES SUIVANTES ET COMPLÉTER!)
        _ = buf;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "allocations simples" {
    var buffer: [128]u8 = undefined;
    var recycle = AllocateurRecycle.init(&buffer);
    const allocator = recycle.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u8);
    const c = try allocator.create(u8);
    const d = try allocator.create(u8);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 1 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(c);

    const e = try allocator.create(u8);
    try expectEqual(c, e);

    const f = try allocator.create(u8);
    try expect(@intFromPtr(d) + 1 <= @intFromPtr(f));
}

test "allocations à plusieurs octets" {
    var buffer: [128]u8 = undefined;
    var recycle = AllocateurRecycle.init(&buffer);
    const allocator = recycle.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u64);
    const c = try allocator.create(u8);
    const d = try allocator.create(u16);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 8 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(a);
    allocator.destroy(b);
    allocator.destroy(c);
    allocator.destroy(d);

    const e = try allocator.create(u24);
    try expectEqual(@intFromPtr(b), @intFromPtr(e));

    const f = try allocator.create(u16);
    try expectEqual(@intFromPtr(d), @intFromPtr(f));

    const g = try allocator.create(u16);
    try expect(@intFromPtr(d) + 2 <= @intFromPtr(g));
}

test "allocation de tableaux" {
    var buffer: [128]u8 = undefined;
    var recycle = AllocateurRecycle.init(&buffer);
    const allocator = recycle.allocator();

    const a = try allocator.alloc(u8, 1);
    const b = try allocator.alloc(u32, 10);
    const c = try allocator.create(u64);

    try expect(@intFromPtr(&a[0]) + 1 <= @intFromPtr(&b[0]));
    try expectEqual(10, b.len);
    try expect(@intFromPtr(&b[9]) + 4 <= @intFromPtr(c));

    allocator.free(b);

    const d = try allocator.alloc(u64, 4);
    try expectEqual(@intFromPtr(b.ptr), @intFromPtr(d.ptr));
}
