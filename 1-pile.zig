const std = @import("std");

const AllocateurPile = struct {
    buffer: []u8,
    next: usize,

    /// Crée un allocateur à pile gérant la zone de mémoire délimitée
    /// par la tranche `buffer`.
    fn init(buffer: []u8) AllocateurPile {
        return .{
            .buffer = buffer,
            .next = 0,
        };
    }

    /// Retourne l’interface générique d’allocateur correspondant à
    /// cet allocateur à pile.
    fn allocator(self: *AllocateurPile) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .free = std.mem.Allocator.noFree,
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
        const self: *AllocateurPile = @ptrCast(@alignCast(ctx));

        // par la suite, `self.buffer` et `self.next` désignent les deux
        // champs de l’allocateur

        // obtient le pointeur vers l'address actuel 
        // self.buffer.ptr = pointeur qui pointe à l'addresse de début du buffer
        // self.next = pointe à la prochaine case disponible pour des allocations dans le buffer
        const current_addr = self.buffer.ptr + self.next;

        // l'index où on est en bytes dans le buffer (taille relative)
        var idx = @intFromPtr(current_addr) - @intFromPtr(self.buffer.ptr);

        // on voit la possibilité de faire une nouvelle allocation en comparant
        // la taille du buffer avec la position actuelle plus la taille des bytes qu'on veut allouer
        if (idx + len > self.buffer.len ) { // si la taille de ce qu'on veut allouer est trop grad, on ne fait rien
            return null;
        }

        // transforme l'alignement (enum ex: 2^0, 2^1, 2^2...) en entier et après en usize pour qu'on puisse réaliser des opérations avec idx (usize)
        const int_alignment = @as(usize, 1) << @intFromEnum(alignment);
        // on réalise l'alignement : si index n'est pas multiple de l'alignement,
        // on met à jour l'index pour qu'il devient un multiple
        if (idx % int_alignment != 0) {
            idx += int_alignment - (idx % int_alignment);
        }

        // le pointeur aligné devient l'index courant + le pointeur qui pointe au
        // début du buffer
        const ptr_aligned = self.buffer.ptr + idx;

        self.next = idx + len;

        // retourne un pointeur vers l'addresse où l'allocation doit être faite
        return ptr_aligned; 
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "allocations simples" {
    var buffer: [4]u8 = undefined;
    var pile = AllocateurPile.init(&buffer);
    const allocator = pile.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u8);
    const c = try allocator.create(u8);
    const d = try allocator.create(u8);
    const e = allocator.create(u8);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 1 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));
    try expectEqual(error.OutOfMemory, e);

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);
}

test "allocations à plusieurs octets" {
    var buffer: [32]u8 = undefined;
    var pile = AllocateurPile.init(&buffer);
    const allocator = pile.allocator();

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
}

test "allocation de tableaux" {
    var buffer: [128]u8 = undefined;
    var pile = AllocateurPile.init(&buffer);
    const allocator = pile.allocator();

    const a = try allocator.alloc(u8, 1);
    const b = try allocator.alloc(u32, 10);
    const c = try allocator.create(u64);

    try expect(@intFromPtr(&a[0]) + 1 <= @intFromPtr(&b[0]));
    try expectEqual(10, b.len);
    try expect(@intFromPtr(&b[9]) + 4 <= @intFromPtr(c));
}
