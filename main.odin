package main

import "vendor:microui"
import rl "vendor:raylib"
import "core:math"
import "core:fmt"
import "core:strings"
import "core:math/linalg"
import "base:intrinsics"
import rt "base:runtime"

Node_Id :: distinct uint

Vec2 :: rl.Vector2

Short_String :: struct {
   value: [64]u8,
   len: int,
}

to_short_string :: proc(str: string) -> Short_String {
   result: Short_String
   str_u8 := transmute([]u8)str
   result.len = min(len(result.value - 1), len(str))
   copy_slice(dst = result.value[:result.len], src = str_u8[:result.len])
   result.value[result.len + 1] = 0
   return result
}

short_string_to_string :: proc(str: ^Short_String) -> string {
   return cast(string)(str.value[:str.len])
}

short_string_to_cstr :: proc(str: ^Short_String) -> cstring {
   return cast(cstring)(&str.value[0])
}

short_string_add_char :: proc(str: ^Short_String, char: u8) {
   if str.len + 1 >= len(str.value) {
      return
   }

   str.value[str.len] = char
   str.len += 1
}

short_string_remove_char :: proc(str: ^Short_String) {
   str.len = max(0, str.len - 1)
   str.value[str.len] = 0
}

Node_Style_Id :: distinct uint
Node_Style :: struct {
   id: Node_Style_Id,
   style_name: Short_String,
   outer_color: rl.Color,
   radius: f32,
   border: f32,
   inner_color: rl.Color,
}

node_style_id_alloc := Node_Style_Id(0)
node_styles: [dynamic]Node_Style

get_style_index_template :: proc(style_id: $I, node_styles: []$T) -> ^T {
   for &style in node_styles {
      if style.id == style_id {
         return &style
      }
   }
   // This shouldn't really run
   inject_at(&node_styles, 0, DEFAULT_NODE_STYLE)
   return &node_styles[0]
}

get_node_style :: proc(style_id: Node_Style_Id) -> ^Node_Style {
   return get_style(style_id, node_styles[:])
}

get_node_style_index :: proc(style_id: Node_Style_Id) -> int {
   return get_style_index(style_id, node_styles[:])
}

Edge_Style_Id :: distinct uint
Edge_Style :: struct {
   id: Edge_Style_Id,
   style_name: Short_String,
   color: rl.Color,
   type: Edge_Type,
   thickness: f32,
}

edge_style_id_alloc := Edge_Style_Id(0)
edge_styles: [dynamic]Edge_Style

get_style_index :: proc(style_id: $I, styles: []$T) -> int 
   where intrinsics.type_field_type(T, "id") == I {
   for &style, index in styles {
      if style.id == style_id {
         return index
      }
   }
   return 0
}

get_style :: proc(style_id: $I, styles: []$T) -> ^T {
   return &styles[get_style_index(style_id, styles)]
}

get_edge_style :: proc(style_id: Edge_Style_Id) -> ^Edge_Style {
   return get_style(style_id, edge_styles[:])
}

get_edge_style_index :: proc(style_id: Edge_Style_Id) -> int {
   return get_style_index(style_id, edge_styles[:])
}

get_next_style :: proc(style_id: $I, styles: []$T) -> Maybe(^T) {
   cur_index := get_style_index(style_id, styles)
   if cur_index < len(styles) - 1 {
      return &styles[cur_index + 1]
   }
   return nil
}

get_next_edge_style :: proc(style_id: Edge_Style_Id) -> Maybe(^Edge_Style) {
   return get_next_style(style_id, edge_styles[:])
}

get_next_node_style :: proc(style_id: Node_Style_Id) -> Maybe(^Node_Style) {
   return get_next_style(style_id, node_styles[:])
}

get_prev_style :: proc(style_id: $I, styles: []$T) -> Maybe(^T) {
   cur_index := get_style_index(style_id, styles)
   if cur_index > 0 {
      return &styles[cur_index - 1]
   }
   return nil
}

get_prev_edge_style :: proc(style_id: Edge_Style_Id) -> Maybe(^Edge_Style) {
   return get_prev_style(style_id, edge_styles[:])
}

get_prev_node_style :: proc(style_id: Node_Style_Id) -> Maybe(^Node_Style) {
   return get_prev_style(style_id, node_styles[:])
}

Node :: struct {
   id: Node_Id,
   style: Node_Style_Id,
   name: Short_String,
   pos: rl.Vector2,
}

Edge_Type :: enum {
   Undirected,
   Directed,
   Both,
}

Edge :: struct {
   style: Edge_Style_Id,
   label: Short_String,
   node_1: Node_Id,
   node_2: Node_Id,
}

DEFAULT_EDGE :: Edge{
   label = {},
   style = Edge_Style_Id(0),
   node_1 = {},
   node_2 = {},
}

node_allocator := Node_Id(1)

nodes: [dynamic]Node
edges: [dynamic]Edge
colors: [dynamic]rl.Color

add_node :: proc(node: Node) {
   node := node
   node.id = node_allocator
   node_allocator += 1
   append(&nodes, node)
}

DEFAULT_NODE_STYLE := Node_Style {
   id = 0,
   style_name = to_short_string("Default"),
   outer_color = rl.BLACK,
   radius = 50,
   border = 5,
   inner_color = rl.WHITE,
}
#assert(intrinsics.type_struct_field_count(Node_Style) == 6)

DEFAULT_EDGE_STYLE := Edge_Style {
   id = 0,
   style_name = to_short_string("Default"),
   color = rl.BLACK,
   type = .Directed,
   thickness = 2,
}
#assert(intrinsics.type_struct_field_count(Edge_Style) == 5)

node_id_to_index :: proc(node_id: Node_Id) -> (int, bool) {
   for node, index in nodes {
      if node.id == node_id {
         return index, true
      }
   }
   return {}, false
}

mu_ctx: microui.Context

node_is_clicked :: proc(node: Node, mouse_pos: rl.Vector2) -> bool {
   style := get_node_style(node.style)
   return style.radius + style.border >= linalg.distance(mouse_pos, node.pos)
}

edge_to_nodes :: proc(edge: Edge) -> Maybe([2]^Node) {
   edge_start: ^Node
   edge_start_ok := false
   for &node in nodes {
      if node.id == edge.node_1 {
         edge_start = &node
         edge_start_ok = true
         break
      }
   }
   if !edge_start_ok {
      return nil
   }

   edge_end: ^Node
   edge_end_ok := false
   for &node in nodes {
      if node.id == edge.node_2 {
         edge_end = &node
         edge_end_ok = true
      }
   }
   if !edge_end_ok {
      return nil
   }

   return [2]^Node{edge_start, edge_end}
}

edge_to_ends :: proc(edge: Edge) -> Maybe([2]rl.Vector2) {
   nodes, nodes_ok := edge_to_nodes(edge).([2]^Node)
   if !nodes_ok {
      return nil
   }
   return [2]rl.Vector2{nodes[0].pos, nodes[1].pos}
}

find_edge_index :: proc(node_1: Node_Id, node_2: Node_Id) -> Maybe(int) {
   for edge2, index in edges {
      if (node_1 == edge2.node_1 && node_2 == edge2.node_2) {
         return index
      }
      if (node_2 == edge2.node_1 && node_1 == edge2.node_2) {
         return index
      }
   }
   return nil
}

Style_Editor_Mode :: enum {
   Node,
   Edge,
}

main :: proc() {
   append(&colors, rl.BLACK)

   rl.InitWindow(1600, 900, "Graph Editor")
   rl.SetTargetFPS(60)

   microui.init(&mu_ctx)

   style_editor_mode := Style_Editor_Mode.Edge
   node_style_editor_id := Node_Style_Id(0)
   edge_style_editor_id := Edge_Style_Id(0)

   append(&node_styles, DEFAULT_NODE_STYLE)
   append(&edge_styles, DEFAULT_EDGE_STYLE)
   edge_style_id_alloc += 1
   append(&edge_styles, Edge_Style{
      id = edge_style_id_alloc,
      style_name = to_short_string("red"),
      color = rl.RED,
      type = .Undirected,
      thickness = 3,
   })

   {
      start_node := Node {
         id = 0, // We will overwrite it by adding it 
         style = Node_Style_Id(0), // Default
         name = to_short_string("s"),
         pos = {},
      }
      add_node(start_node)
   }

   font := rl.LoadFont("/usr/share/fonts/noto/NotoSans-Medium.ttf")

   camera_pos := rl.Vector2{}
   zoom_factor := f32(0)

   Mode_None :: struct {}
   Mode_Add_Node :: struct {}
   Mode_Add_Edge :: struct {node: Node_Id}
   Mode_Edit_Node :: struct {node: Node_Id}
   Mode_Edit_Edge :: struct {node_1: Node_Id, node_2: Node_Id}
   Mode_Delete_Node :: struct {}

   Mode :: union {
      Mode_None, Mode_Add_Node, Mode_Add_Edge, Mode_Edit_Node, Mode_Edit_Edge, Mode_Delete_Node
   }

   Node_Movement :: struct {
      node_id: Node_Id,
   }

   mode: Mode = Mode_Edit_Node{}
   node_movement: Maybe(Node_Movement)

   gui_offset := f32(400)

   for !rl.WindowShouldClose() {
      width := cast(f32)rl.GetScreenWidth()
      height := cast(f32)rl.GetScreenHeight()
      log_sb: strings.Builder
      defer strings.builder_destroy(&log_sb)

      zoom_factor -= rl.GetMouseWheelMove()
      zoom := math.pow(0.8, zoom_factor)

      mouse_move := rl.GetMouseDelta() / zoom
      if rl.IsMouseButtonDown(.MIDDLE) {
         camera_pos -= mouse_move
      }

      camera := rl.Camera2D{
         offset = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
         target = camera_pos,
         rotation = 0,
         zoom = zoom,
      }

      mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
      gui_background_rect := rl.Rectangle{width - gui_offset, 0, gui_offset, height}
      mouse_in_main := !rl.CheckCollisionPointRec(rl.GetMousePosition(), gui_background_rect)

      if rl.IsMouseButtonPressed(.RIGHT) && mouse_in_main {
         for &start_node in nodes {
            if node_is_clicked(start_node, mouse_pos) {
               mode = Mode_Edit_Node{start_node.id}
               break
            }
         }

         for &edge in edges {
            ends, ends_ok := edge_to_ends(edge).([2]rl.Vector2)
            if !ends_ok {
               continue
            }
            if rl.CheckCollisionPointLine(
               rl.GetWorldToScreen2D(mouse_pos, camera),
               rl.GetWorldToScreen2D(ends[0], camera), 
               rl.GetWorldToScreen2D(ends[1], camera), 
               10,
            ) {
               mode = Mode_Edit_Edge{node_1 = edge.node_1, node_2 = edge.node_2}
            }
         }
      }

      if node_move, node_move_ok := node_movement.(Node_Movement); node_move_ok {
         if rl.IsMouseButtonDown(.LEFT) {
            for &node in nodes {
               if node.id == node_move.node_id {
                  node.pos += mouse_move
               }
            }
         }
         else {
            node_movement = nil
         }
      }
      else if rl.IsMouseButtonPressed(.LEFT) && mouse_in_main {
         if _, ok := mode.(Mode_Delete_Node); ok {
            #reverse for &node, index in nodes {
               if node_is_clicked(node, mouse_pos) {
                  ordered_remove(&nodes, index)
                  #reverse for edge, index in edges {
                     if edge.node_1 == node.id || edge.node_2 == node.id {
                        unordered_remove(&edges, index)
                     }
                  }
                  break
               }
            }
         }
         else {
            for &start_node in nodes {
               if node_is_clicked(start_node, mouse_pos) {
                  node_movement = Node_Movement{start_node.id}
               }
            }
         }
      }
      
      edge_click := rl.IsMouseButtonPressed(.EXTRA)

      _, is_mode_add_edge := mode.(Mode_Add_Edge)

      if !is_mode_add_edge && edge_click && mouse_in_main {
         edge_click = false
         for &node in nodes {
            if node_is_clicked(node, mouse_pos) {
               mode = Mode_Add_Edge{node.id}
               break
            }
         }
      }

      #partial switch &v in mode {
         case Mode_None:
         case Mode_Add_Node:
            if rl.IsMouseButtonPressed(.LEFT) && node_movement == nil && mouse_in_main {
               node := Node {
                  // node_id
                  style = get_node_style(node_style_editor_id).id,
                  name = {},
                  // pos
               }
               #assert(intrinsics.type_struct_field_count(Node) == 4)
               node.pos = mouse_pos
               add_node(node)
            } 
         case Mode_Add_Edge:
            if edge_click && mouse_in_main {
               edge_click = false
               for &node in nodes {
                  if node_is_clicked(node, mouse_pos) {
                     if (v.node == node.id) {
                        continue
                     }
                     edge := DEFAULT_EDGE
                     edge.style = get_edge_style(edge_style_editor_id).id
                     edge.node_1 = v.node
                     edge.node_2 = node.id
                     
                     if index, index_ok := find_edge_index(edge.node_1, edge.node_2).(int); index_ok {
                        unordered_remove(&edges, index)
                     }
                     else {
                        append(&edges, edge)
                     }
                  }
               }
               mode = Mode_None{}
            }
      }

      rl.BeginDrawing()
      rl.ClearBackground(rl.WHITE)
      rl.BeginMode2D(camera)

      if mode_add_edge, mode_add_edge_ok := mode.(Mode_Add_Edge); mode_add_edge_ok {
         fmt.sbprintf(&log_sb, "EDGE ADD ")
         for &node in nodes {
            if node.id == mode_add_edge.node {
               edge_start := node.pos
               edge_end := mouse_pos
               rl.DrawLineV(edge_start, edge_end, rl.BLUE)
               break
            }
         }
      }

      rot_left := linalg.matrix2_rotate_f32(linalg.RAD_PER_DEG * 15)
      rot_right := linalg.matrix2_rotate_f32(linalg.RAD_PER_DEG * -15)
      rot_90 := linalg.matrix2_rotate_f32(linalg.RAD_PER_DEG * 90)
      for &edge in edges {
         style := get_edge_style(edge.style)
         nodes, nodes_ok := edge_to_nodes(edge).([2]^Node)
         if !nodes_ok {
            continue
         }
         pos1 := nodes[0].pos
         style1 := get_node_style(nodes[0].style)
         rad1 := style1.radius + style1.border

         pos2 := nodes[1].pos
         style2 := get_node_style(nodes[1].style)
         rad2 := style2.radius + style2.border

         normal := linalg.normalize(pos2 - pos1) // Normal vector from pos1 to pos2

         pos1 += normal * rad1
         pos2 -= normal * rad2


         ARROW_LENGTH :: 20
         draw_arrow :: proc(pos1: rl.Vector2, pos2: rl.Vector2, normal: rl.Vector2, rot_left: matrix[2, 2]f32, rot_right: matrix[2, 2]f32, style: ^Edge_Style) {
            rl.DrawLineEx(pos2, pos2 - rot_left * normal * ARROW_LENGTH, style.thickness, style.color)
            rl.DrawLineEx(pos2, pos2 - rot_right * normal * ARROW_LENGTH, style.thickness, style.color)
            rl.DrawLineEx(pos1, pos2, style.thickness, style.color)
         }
         switch style.type {
            case .Undirected:
               rl.DrawLineEx(pos1, pos2, style.thickness, style.color)
            case .Directed:
               draw_arrow(pos1, pos2, normal, rot_left, rot_right, style)
            case .Both:
               perp := normal * rot_90 * 6
               draw_arrow(pos1 + perp, pos2 + perp, normal, rot_left, rot_right, style)
               draw_arrow(pos2 - perp, pos1 - perp, -normal, rot_left, rot_right, style)
         }
      }
      for &start_node in nodes {
         style := get_node_style(start_node.style)
         rl.DrawCircleV(start_node.pos, style.radius + style.border, style.outer_color)
         rl.DrawCircleV(start_node.pos, style.radius, style.inner_color)
         font_size :: 35
         cstr := short_string_to_cstr(&start_node.name)
         text_size := rl.MeasureTextEx(font, cstr, font_size, 0)
         rl.DrawTextEx(font, cstr, start_node.pos - text_size / 2, font_size, 0, rl.BLACK)
      }
      rl.EndMode2D()
      rl.BeginMode2D(rl.Camera2D{
         zoom = 1
      })
      background_color := rl.GRAY
      background_color.a = 128
      rl.DrawRectangleRec(gui_background_rect, background_color)

      #partial switch v in mode {
         case Mode_Edit_Node:
            node_id := v.node
            if index, index_ok := node_id_to_index(node_id); index_ok {
               start_node := &nodes[index]
               cstr := short_string_to_cstr(&start_node.name)
               gui_pos := [2]f32{30, 30}

               gui_size := [2]f32{200, 100}
               res := rl.GuiTextInputBox(
                  rl.Rectangle{gui_pos.x, gui_pos.y, gui_size.x, gui_size.y}, 
                  "Node name",
                  "",
                  "",
                  cstr, 
                  cast(i32)len(start_node.name.value), 
                  nil,
               )
               gui_pos.y += gui_size.y

               gui_size = [2]f32{200, 200}
               /*rl.GuiColorPicker(
                  rl.Rectangle{
                     gui_pos.x, gui_pos.y, gui_size.x, gui_size.y
                  }, 
                  "inner_color", 
                  &start_node.inner_color
               )*/
               if res == 0 {
                  mode = Mode_None{}
               }
            }
            else {
               mode = Mode_None{}
            }
         case Mode_Edit_Edge:
            index, index_ok := find_edge_index(v.node_1, v.node_2).(int)
            if !index_ok {
               break
            }

            gui_pos := Vec2{30, 30}
            gui_size := Vec2{200, 100}
            cstr := short_string_to_cstr(&edges[index].label)

            if rl.GuiTextInputBox(
               rl.Rectangle{gui_pos.x, gui_pos.y, gui_size.x, gui_size.y}, 
               "Node name",
               "",
               "",
               cstr, 
               cast(i32)len(edges[index].label.value), 
               nil,
            ) == 0 {
               mode = Mode_None{}
               break
            }
      }

      BUTTON_SIZE :: 56

      {
         x := width - gui_offset + 10
         {
            add_text: cstring = "Add"
            if _, ok := mode.(Mode_Add_Node); ok {
               add_text = "[Add]"
            }
            if rl.GuiButton({x = x, y = 30, width = BUTTON_SIZE, height = BUTTON_SIZE}, add_text) {
               mode = Mode_Add_Node{}
            }
            x += BUTTON_SIZE + 10
         }

         {
            delete_text: cstring = "Delete"
            if _, ok := mode.(Mode_Delete_Node); ok {
               delete_text = "[Delete]"
            }
            if rl.GuiButton({x = x, y = 30, width = BUTTON_SIZE, height = BUTTON_SIZE}, delete_text) {
               mode = Mode_Delete_Node{}
            }
            x += BUTTON_SIZE + 10
         }

         {
            normal_text: cstring = "Normal"
            if _, ok := mode.(Mode_None); ok {
               normal_text = "[Normal]"
            }
            if rl.GuiButton({x = x, y = 30, width = BUTTON_SIZE, height = BUTTON_SIZE}, normal_text) {
               mode = Mode_None{}
            }
            x += BUTTON_SIZE + 10
         }

         {
            node_text: cstring = "Node\nStyles" if style_editor_mode != .Node else "[Node]\n[Styles]"
            if rl.GuiButton({x = x, y = 30, width = BUTTON_SIZE, height = BUTTON_SIZE}, node_text) {
               style_editor_mode = .Node
            }
            x += BUTTON_SIZE + 10
         }

         {
            edge_text: cstring = "Edge\nStyles" if style_editor_mode != .Edge else "[Edge]\n[Styles]"
            if rl.GuiButton({x = x, y = 30, width = BUTTON_SIZE, height = BUTTON_SIZE}, edge_text) {
               style_editor_mode = .Edge
            }
            x += BUTTON_SIZE + 10
         }
      }

      switch style_editor_mode {
      case .Node:
         y := cast(f32)30 + BUTTON_SIZE + 10
         x := width - 300
         {
            cur_style := get_node_style(node_style_editor_id)
            fmt.sbprintfln(&log_sb, "Style: {} {}/{}", 
               cur_style.id, 
               get_node_style_index(cur_style.id) + 1, 
               len(edge_styles)
            )
            prev_style := get_prev_node_style(cur_style.id)
            next_style := get_next_node_style(cur_style.id)
            prev_pressed := false
            next_pressed := false
            delete_pressed := false
            new_pressed := false
            if prev_style != nil && rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "Previous") {
               prev_pressed = true
            }
            x += BUTTON_SIZE + 10
            if next_style != nil && rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "Next") {
               next_pressed = true
            }
            x += BUTTON_SIZE + 10
            if cur_style.id != 0 && rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "Delete") {
               delete_pressed = true
            }
            x += BUTTON_SIZE + 10
            if rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "New") {
               new_pressed = true
            }
            if prev_pressed {
               node_style_editor_id = prev_style.?.id
            }
            else if next_pressed {
               node_style_editor_id = next_style.?.id
            }
            else if delete_pressed {
               index_to_del := get_node_style_index(cur_style.id)
               cur_style = prev_style.?
               ordered_remove(&edge_styles, index_to_del)
            }
            else if new_pressed {
               new_style := cur_style^
               node_style_id_alloc += 1
               new_style.id = node_style_id_alloc
               edge_style_editor_id = edge_style_id_alloc
               append(&node_styles, new_style)
            }
         }
         y += BUTTON_SIZE + 10 
         x = width - 300
         style := get_node_style(node_style_editor_id)
         name_rect := rl.Rectangle{x = cast(f32)x, y = cast(f32)y, width = 200, height = 40}
         y += 40 + 10
         if style.id == Node_Style_Id(0) {
            temp_str := to_short_string("default")
            cstr := short_string_to_cstr(&temp_str)
            rl.GuiTextBox(
               name_rect,
               cstr,
               cast(i32)len(temp_str.value),
               false,
            )
         }
         else {
            cstr := short_string_to_cstr(&style.style_name)
            rl.GuiTextBox(
               name_rect,
               cstr,
               cast(i32)len(style.style_name.value),
               true,
            )
            {
               outer_color_picker_rect := rl.Rectangle{x = x, y = y, width = 200, height = 200}
               y += outer_color_picker_rect.height
               y += 10
               rl.GuiColorPicker(outer_color_picker_rect, "", &style.outer_color)
            }

            {
               slider_rect := rl.Rectangle{x = x, y = y, width = 200, height = 30}
               y += slider_rect.height
               y += 10
               rt.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
               cstr_val := fmt.ctprint(style.radius)
               rl.GuiSlider(slider_rect, "radius", cstr_val, &style.radius, 0, 150)
               style.radius = math.round(style.radius)
            }

            {
               slider_rect := rl.Rectangle{x = x, y = y, width = 200, height = 30}
               y += slider_rect.height
               y += 10
               rt.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
               cstr_val := fmt.ctprint(style.border)
               rl.GuiSlider(slider_rect, "border", cstr_val, &style.border, 0, 30)
               style.border = math.round(style.border)
            }

            {
               inner_color_picker_rect := rl.Rectangle{x = x, y = y, width = 200, height = 200}
               y += inner_color_picker_rect.height
               y += 10
               rl.GuiColorPicker(inner_color_picker_rect, "", &style.inner_color)
            }

         }
      case .Edge:
         y := cast(f32)30 + BUTTON_SIZE + 10
         x := width - 300
         {
            cur_style := get_edge_style(edge_style_editor_id)
            fmt.sbprintfln(&log_sb, "Style: {} {}/{}", 
               cur_style.id, 
               get_edge_style_index(cur_style.id) + 1, 
               len(edge_styles)
            )
            prev_style := get_prev_edge_style(cur_style.id)
            next_style := get_next_edge_style(cur_style.id)
            prev_pressed := false
            next_pressed := false
            delete_pressed := false
            new_pressed := false
            if prev_style != nil && rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "Previous") {
               prev_pressed = true
            }
            x += BUTTON_SIZE + 10
            if next_style != nil && rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "Next") {
               next_pressed = true
            }
            x += BUTTON_SIZE + 10
            if cur_style.id != 0 && rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "Delete") {
               delete_pressed = true
            }
            x += BUTTON_SIZE + 10
            if rl.GuiButton({x = x, y = y, width = BUTTON_SIZE, height = BUTTON_SIZE}, "New") {
               new_pressed = true
            }
            if prev_pressed {
               edge_style_editor_id = prev_style.?.id
            }
            else if next_pressed {
               edge_style_editor_id = next_style.?.id
            }
            else if delete_pressed {
               index_to_del := get_edge_style_index(cur_style.id)
               cur_style = prev_style.?
               ordered_remove(&edge_styles, index_to_del)
            }
            else if new_pressed {
               new_style := cur_style^
               edge_style_id_alloc += 1
               new_style.id = edge_style_id_alloc
               edge_style_editor_id = edge_style_id_alloc
               append(&edge_styles, new_style)
            }
         }
         y += BUTTON_SIZE + 10 
         x = width - 300
         style := get_edge_style(edge_style_editor_id)
         name_rect := rl.Rectangle{x = cast(f32)x, y = cast(f32)y, width = 200, height = 40}
         y += 40 + 10
         if style.id == Edge_Style_Id(0) {
            temp_str := to_short_string("default")
            cstr := short_string_to_cstr(&temp_str)
            rl.GuiTextBox(
               name_rect,
               cstr,
               cast(i32)len(temp_str.value),
               false,
            )
         }
         else {
            cstr := short_string_to_cstr(&style.style_name)
            rl.GuiTextBox(
               name_rect,
               cstr,
               cast(i32)len(style.style_name.value),
               true,
            )
            color_picker_rect := rl.Rectangle{x = x, y = y, width = 200, height = 200}
            y += color_picker_rect.height
            y += 10
            rl.GuiColorPicker(color_picker_rect, "", &style.color)
            {
               rt.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
               text_cstr := fmt.ctprintf("Type: {}", style.type)
               rl.DrawText(text_cstr, cast(i32)x, cast(i32)y, 20, rl.BLACK)
               y += 20
               y += 10
            }

            x := width - 300
            for type in Edge_Type {
               type_cstr := fmt.ctprint(type)
               if rl.GuiButton({x, y, 200, 25}, type_cstr) {
                  style.type = type
               }
               y += 30
            }
         }
      }

      {
         if _, ok := mode.(Mode_Add_Node); ok {
            color := rl.Color{0, 128, 128, 0x40}
            rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 20, color)
         }
         if _, ok := mode.(Mode_Delete_Node); ok {
            color := rl.Color{255, 64, 64, 0x40}
            rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 20, color)
         }
         fmt.sbprintf(&log_sb, "{} {}", mouse_pos, node_movement)
         cstr, _ := strings.to_cstring(&log_sb)
         rl.DrawText(cstr, 0, 0, 30, rl.BLACK)
      }
      rl.EndMode2D()
      rl.EndDrawing()
   }
}
