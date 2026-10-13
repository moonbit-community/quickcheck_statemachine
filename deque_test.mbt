///|
// Deque model and property:
// The mutable system is the standard-library Deque. The model is a plain Array
// with the same logical order. Every command returns a snapshot rich enough to
// check mutation results plus the observation APIs that should always agree
// with the logical sequence: to_array, iterators, front/back, indexed access,
// views, length, emptiness, and capacity invariants.
enum DequeCommand {
  DequeConstruct(Array[Int32], Int32)
  DequeFromIter(Array[Int32])
  DequeFromJson(Array[Int32])
  DequeReset(Array[Int32], Int32)
  DequeResetFromJson(Array[Int32])
  DequeResetWrapped(Array[Int32])
  DequePushBack(Int32)
  DequePushFront(Int32)
  DequePopBack
  DequePopFront
  DequeUnsafePopBack
  DequeUnsafePopFront
  DequeFront
  DequeBack
  DequeGet(Int32)
  DequeAt(Int32)
  DequeSet(Int32, Int32)
  DequeInsert(Int32, Int32)
  DequeRemove(Int32)
  DequeClear
  DequeTruncate(Int32)
  DequeDrain(Int32, Int32)
  DequeDrainToEnd(Int32)
  DequeRetainAtLeast(Int32)
  DequeRetainMapEven(Int32)
  DequeRetainEvenIndex
  DequeRetainMapAddCallIndex
  DequeExtractBelow(Int32)
  DequeFilterAtLeast(Int32)
  DequeFilterEvenIndex
  DequeMapAdd(Int32)
  DequeMapAddCallIndex
  DequeMapiAddIndex
  DequeChunkByNondecreasing
  DequeChunkByEvenBoundary
  DequeFlatten(Array[Array[Int32]])
  DequeFlattenWrapped(Array[Array[Int32]])
  DequeFlattenSlack(Array[Array[Int32]])
  DequeFlattenWrappedSlack(Array[Array[Int32]])
  DequeReverseInPlace
  DequeReserveCapacity(Int32)
  DequeShrinkToFit
  DequeAppend(Array[Int32])
  DequeAppendSelf
  DequeAppendWrapped(Array[Int32])
  DequeAdd(Array[Int32])
  DequeAddSelf
  DequeAddWrapped(Array[Int32])
  DequeCopy
  DequeRev
  DequeToJson
  DequeContains(Int32)
  DequeSearch(Int32)
  DequeBinarySearch(Int32)
  DequeBinarySearchBy(Int32)
  DequeEqual(Array[Int32])
  DequeNotEqual(Array[Int32])
  DequeCompare(Array[Int32])
  DequeLessThan(Array[Int32])
  DequeLessEqual(Array[Int32])
  DequeGreaterThan(Array[Int32])
  DequeGreaterEqual(Array[Int32])
  DequeShuffleZero
  DequeShuffleInPlaceZero
  DequeShuffleLinear
  DequeShuffleInPlaceLinear
  DequeBlitTo(Array[Int32], Int32, Int32, Int32)
  DequeBlitToWrappedDst(Array[Int32], Int32, Int32, Int32)
  DequeBlitSelf(Int32, Int32, Int32)
  DequeChunks(Int32)
} derive(Eq, Debug)

///|
enum DequeResult {
  DequeDone
  DequeOptional(Int32?)
  DequeItem(Int32)
  DequeInt(Int32)
  DequeItems(Array[Int32])
  DequeNestedItems(Array[Array[Int32]])
  DequeBool(Bool)
  DequeSearchResult(Result[Int32, Int32])
} derive(Eq, Debug)

///|
struct DequeModel {
  values : Array[Int32]
  capacity : Int32
} derive(Eq, Debug)

///|
struct DequeObservation {
  contents : Array[Int32]
  length : Int32
  is_empty : Bool
  front : Int32?
  back : Int32?
  iter_contents : Array[Int32]
  rev_iter_contents : Array[Int32]
  each_contents : Array[Int32]
  rev_each_contents : Array[Int32]
  eachi_contents : Array[(Int32, Int32)]
  iter2_contents : Array[(Int32, Int32)]
  rev_eachi_contents : Array[(Int32, Int32)]
  rev_iter2_contents : Array[(Int32, Int32)]
  get_contents : Array[Int32?]
  at_contents : Array[Int32]
  view_contents : Array[Int32]
  capacity : Int32
} derive(Eq, Debug)

///|
struct DequeExpectedObservation {
  values : Array[Int32]
  capacity_min : Int32
  exact_capacity : Int32?
} derive(Eq, Debug)

///|
struct DequeResponse {
  result : DequeResult
  contents : Array[Int32]
  length : Int32
  is_empty : Bool
  front : Int32?
  back : Int32?
  iter_contents : Array[Int32]
  rev_iter_contents : Array[Int32]
  each_contents : Array[Int32]
  rev_each_contents : Array[Int32]
  eachi_contents : Array[(Int32, Int32)]
  iter2_contents : Array[(Int32, Int32)]
  rev_eachi_contents : Array[(Int32, Int32)]
  rev_iter2_contents : Array[(Int32, Int32)]
  get_contents : Array[Int32?]
  at_contents : Array[Int32]
  view_contents : Array[Int32]
  capacity : Int32
  derived : Array[DequeObservation]
} derive(Eq, Debug)

///|
struct DequeSystem {
  mut deque : @deque.Deque[Int32]
} derive(Eq, Debug)

///|
fn deque_model(
  values : Array[Int32],
  capacity~ : Int32 = values.length(),
) -> DequeModel {
  { values, capacity, }
}

///|
fn deque_empty_model() -> DequeModel {
  deque_model([], capacity=0)
}

///|
fn deque_empty_system() -> DequeSystem {
  { deque: @deque.from_array([]), }
}

///|
fn deque_wrapped_from_array(values : Array[Int32]) -> @deque.Deque[Int32] {
  let deque = @deque.Deque([], capacity=deque_max(values.length(), 1))
  deque.push_back(0)
  ignore(deque.pop_front())
  for value in values {
    deque.push_back(value)
  }
  deque
}

///|
fn deque_slack_from_array(
  values : Array[Int32],
  wrapped~ : Bool,
) -> @deque.Deque[Int32] {
  let deque = @deque.Deque([], capacity=values.length() + 5)
  if wrapped {
    deque.push_back(0)
    ignore(deque.pop_front())
  }
  for value in values {
    deque.push_back(value)
  }
  deque
}

///|
fn deque_outer_wrapped_from_deques(
  deques : Array[@deque.Deque[Int32]],
) -> @deque.Deque[@deque.Deque[Int32]] {
  let outer = @deque.Deque([], capacity=deques.length() + 5)
  outer.push_back(@deque.from_array([]))
  ignore(outer.pop_front())
  for deque in deques {
    outer.push_back(deque)
  }
  outer
}

///|
fn deque_positioned_from_array(
  values : Array[Int32],
  capacity : Int32,
  head_shift : Int32,
) -> @deque.Deque[Int32] {
  let deque = @deque.Deque([], capacity~)
  if capacity > 0 {
    for _ in 0..<head_shift {
      deque.push_back(0)
      ignore(deque.pop_front())
    }
  }
  for value in values {
    deque.push_back(value)
  }
  deque
}

///|
fn deque_string_positioned_from_array(
  values : Array[String],
  capacity : Int32,
  head_shift : Int32,
) -> @deque.Deque[String] {
  let deque = @deque.Deque([], capacity~)
  if capacity > 0 {
    for _ in 0..<head_shift {
      deque.push_back("__sentinel__")
      ignore(deque.pop_front())
    }
  }
  for value in values {
    deque.push_back(value)
  }
  deque
}

///|
fn deque_front_model(model : Array[Int32]) -> Int32? {
  if model.length() == 0 {
    None
  } else {
    Some(model[0])
  }
}

///|
fn deque_back_model(model : Array[Int32]) -> Int32? {
  let len = model.length()
  if len == 0 {
    None
  } else {
    Some(model[len - 1])
  }
}

///|
fn deque_get_model(model : Array[Int32], index : Int32) -> Int32? {
  if 0 <= index && index < model.length() {
    Some(model[index])
  } else {
    None
  }
}

///|
fn deque_reverse_array(model : Array[Int32]) -> Array[Int32] {
  let reversed : Array[Int32] = []
  for index = model.length(); index > 0; {
    reversed.push(model[index - 1])
    continue index - 1
  }
  reversed
}

///|
fn deque_indexed_model(model : Array[Int32]) -> Array[(Int32, Int32)] {
  let indexed : Array[(Int32, Int32)] = []
  for index in 0..<model.length() {
    indexed.push((index, model[index]))
  }
  indexed
}

///|
fn deque_get_all_from_model(model : Array[Int32]) -> Array[Int32?] {
  let values : Array[Int32?] = []
  for index in 0..<model.length() {
    values.push(Some(model[index]))
  }
  values
}

///|
fn[A] deque_concat(left : Array[A], right : Array[A]) -> Array[A] {
  let result = left.copy()
  for value in right {
    result.push(value)
  }
  result
}

///|
fn deque_views_to_array(deque : @deque.Deque[Int32]) -> Array[Int32] {
  let (first, second) = deque.as_views()
  let values : Array[Int32] = []
  for index in 0..<first.length() {
    values.push(first[index])
  }
  for index in 0..<second.length() {
    values.push(second[index])
  }
  values
}

///|
fn deque_each_to_array(deque : @deque.Deque[Int32]) -> Array[Int32] {
  let values : Array[Int32] = []
  deque.each(value => values.push(value))
  values
}

///|
fn deque_rev_each_to_array(deque : @deque.Deque[Int32]) -> Array[Int32] {
  let values : Array[Int32] = []
  deque.rev_each(value => values.push(value))
  values
}

///|
fn deque_eachi_to_array(deque : @deque.Deque[Int32]) -> Array[(Int32, Int32)] {
  let values : Array[(Int32, Int32)] = []
  deque.eachi((index, value) => values.push((index, value)))
  values
}

///|
fn deque_rev_eachi_to_array(
  deque : @deque.Deque[Int32],
) -> Array[(Int32, Int32)] {
  let values : Array[(Int32, Int32)] = []
  deque.rev_eachi((index, value) => values.push((index, value)))
  values
}

///|
fn deque_get_all(deque : @deque.Deque[Int32]) -> Array[Int32?] {
  let values : Array[Int32?] = []
  for index in 0..<deque.length() {
    values.push(deque.get(index))
  }
  values
}

///|
fn deque_at_all(deque : @deque.Deque[Int32]) -> Array[Int32] {
  let values : Array[Int32] = []
  for index in 0..<deque.length() {
    values.push(deque[index])
  }
  values
}

///|
fn deque_observation(deque : @deque.Deque[Int32]) -> DequeObservation {
  {
    contents: deque.to_array(),
    length: deque.length(),
    is_empty: deque.is_empty(),
    front: deque.front(),
    back: deque.back(),
    iter_contents: deque.iter().to_array(),
    rev_iter_contents: deque.rev_iter().to_array(),
    each_contents: deque_each_to_array(deque),
    rev_each_contents: deque_rev_each_to_array(deque),
    eachi_contents: deque_eachi_to_array(deque),
    iter2_contents: deque.iter2().to_array(),
    rev_eachi_contents: deque_rev_eachi_to_array(deque),
    rev_iter2_contents: deque.rev_iter2().to_array(),
    get_contents: deque_get_all(deque),
    at_contents: deque_at_all(deque),
    view_contents: deque_views_to_array(deque),
    capacity: deque.capacity(),
  }
}

///|
fn deque_snapshot(
  result : DequeResult,
  deque : @deque.Deque[Int32],
  derived~ : Array[DequeObservation] = [],
) -> DequeResponse {
  {
    result,
    contents: deque.to_array(),
    length: deque.length(),
    is_empty: deque.is_empty(),
    front: deque.front(),
    back: deque.back(),
    iter_contents: deque.iter().to_array(),
    rev_iter_contents: deque.rev_iter().to_array(),
    each_contents: deque_each_to_array(deque),
    rev_each_contents: deque_rev_each_to_array(deque),
    eachi_contents: deque_eachi_to_array(deque),
    iter2_contents: deque.iter2().to_array(),
    rev_eachi_contents: deque_rev_eachi_to_array(deque),
    rev_iter2_contents: deque.rev_iter2().to_array(),
    get_contents: deque_get_all(deque),
    at_contents: deque_at_all(deque),
    view_contents: deque_views_to_array(deque),
    capacity: deque.capacity(),
    derived,
  }
}

///|
fn deque_model_response(
  result : DequeResult,
  model : DequeModel,
  derived~ : Array[DequeObservation] = [],
) -> DequeResponse {
  let values = model.values
  {
    result,
    contents: values.copy(),
    length: values.length(),
    is_empty: values.length() == 0,
    front: deque_front_model(values),
    back: deque_back_model(values),
    iter_contents: values.copy(),
    rev_iter_contents: deque_reverse_array(values),
    each_contents: values.copy(),
    rev_each_contents: deque_reverse_array(values),
    eachi_contents: deque_indexed_model(values),
    iter2_contents: deque_indexed_model(values),
    rev_eachi_contents: deque_indexed_model(deque_reverse_array(values)),
    rev_iter2_contents: deque_indexed_model(deque_reverse_array(values)),
    get_contents: deque_get_all_from_model(values),
    at_contents: values.copy(),
    view_contents: values.copy(),
    capacity: model.capacity,
    derived,
  }
}

///|
fn deque_expected_observation(
  values : Array[Int32],
  capacity_min~ : Int32 = values.length(),
  exact_capacity~ : Int32? = None,
) -> DequeExpectedObservation {
  { values: values.copy(), capacity_min, exact_capacity, }
}

///|
fn deque_observation_matches(
  actual : DequeObservation,
  expected : DequeExpectedObservation,
) -> Bool {
  let values = expected.values
  let reversed = deque_reverse_array(values)
  let indexed = deque_indexed_model(values)
  let rev_indexed = deque_indexed_model(reversed)
  let capacity_exact_ok = match expected.exact_capacity {
    Some(capacity) => actual.capacity == capacity
    None => true
  }
  actual.contents == values &&
  actual.length == values.length() &&
  actual.is_empty == (values.length() == 0) &&
  actual.front == deque_front_model(values) &&
  actual.back == deque_back_model(values) &&
  actual.iter_contents == values &&
  actual.rev_iter_contents == reversed &&
  actual.each_contents == values &&
  actual.rev_each_contents == reversed &&
  actual.eachi_contents == indexed &&
  actual.iter2_contents == indexed &&
  actual.rev_eachi_contents == rev_indexed &&
  actual.rev_iter2_contents == rev_indexed &&
  actual.get_contents == deque_get_all_from_model(values) &&
  actual.at_contents == values &&
  actual.view_contents == values &&
  actual.capacity >= values.length() &&
  actual.capacity >= expected.capacity_min &&
  capacity_exact_ok
}

///|
fn deque_observations_match(
  actual : Array[DequeObservation],
  expected : Array[DequeExpectedObservation],
) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    for index = 0; index < actual.length(); {
      if !deque_observation_matches(actual[index], expected[index]) {
        break false
      }
      continue index + 1
    } nobreak {
      true
    }
  }
}

///|
fn deque_array_pop_front(model : Array[Int32]) -> (Int32?, Array[Int32]) {
  let next = model.copy()
  if next.length() == 0 {
    (None, next)
  } else {
    (Some(next.remove(0)), next)
  }
}

///|
fn deque_array_pop_back(model : Array[Int32]) -> (Int32?, Array[Int32]) {
  let next = model.copy()
  (next.pop(), next)
}

///|
fn deque_array_drain(
  model : Array[Int32],
  start : Int32,
  len : Int32,
) -> (Array[Int32], Array[Int32]) {
  let drained : Array[Int32] = []
  let kept : Array[Int32] = []
  let end = start + len
  for index in 0..<model.length() {
    if start <= index && index < end {
      drained.push(model[index])
    } else {
      kept.push(model[index])
    }
  }
  (drained, kept)
}

///|
fn deque_array_drain_to_end(
  model : Array[Int32],
  start : Int32,
) -> (Array[Int32], Array[Int32]) {
  deque_array_drain(model, start, model.length() - start)
}

///|
fn deque_array_retain_at_least(
  model : Array[Int32],
  threshold : Int32,
) -> Array[Int32] {
  let kept : Array[Int32] = []
  for value in model {
    if value >= threshold {
      kept.push(value)
    }
  }
  kept
}

///|
fn deque_retain_map_even_value(value : Int32, delta : Int32) -> Int32? {
  if value % 2 == 0 {
    Some(value + delta)
  } else {
    None
  }
}

///|
fn deque_array_retain_map_even(
  model : Array[Int32],
  delta : Int32,
) -> Array[Int32] {
  let kept : Array[Int32] = []
  for value in model {
    match deque_retain_map_even_value(value, delta) {
      Some(mapped) => kept.push(mapped)
      None => ()
    }
  }
  kept
}

///|
fn deque_array_even_index(model : Array[Int32]) -> Array[Int32] {
  let kept : Array[Int32] = []
  for index, value in model {
    if index % 2 == 0 {
      kept.push(value)
    }
  }
  kept
}

///|
fn deque_array_retain_map_add_call_index(model : Array[Int32]) -> Array[Int32] {
  let kept : Array[Int32] = []
  for index, value in model {
    if index % 2 == 0 {
      kept.push(value + index)
    }
  }
  kept
}

///|
fn deque_array_extract_below(
  model : Array[Int32],
  threshold : Int32,
) -> (Array[Int32], Array[Int32]) {
  let extracted : Array[Int32] = []
  let kept : Array[Int32] = []
  for value in model {
    if value < threshold {
      extracted.push(value)
    } else {
      kept.push(value)
    }
  }
  (extracted, kept)
}

///|
fn deque_array_filter_at_least(
  model : Array[Int32],
  threshold : Int32,
) -> Array[Int32] {
  deque_array_retain_at_least(model, threshold)
}

///|
fn deque_array_map_add(model : Array[Int32], delta : Int32) -> Array[Int32] {
  let mapped : Array[Int32] = []
  for value in model {
    mapped.push(value + delta)
  }
  mapped
}

///|
fn deque_array_map_add_call_index(model : Array[Int32]) -> Array[Int32] {
  let mapped : Array[Int32] = []
  for index, value in model {
    mapped.push(value + index)
  }
  mapped
}

///|
fn deque_array_mapi_add_index(model : Array[Int32]) -> Array[Int32] {
  let mapped : Array[Int32] = []
  for index, value in model {
    mapped.push(value + index)
  }
  mapped
}

///|
fn deque_array_chunk_by_nondecreasing(
  model : Array[Int32],
) -> Array[Array[Int32]] {
  let chunks : Array[Array[Int32]] = []
  for start = 0; start < model.length(); {
    let chunk : Array[Int32] = []
    chunk.push(model[start])
    let next = for index = start + 1; index < model.length() &&
                  model[index - 1] <= model[index]; {
      chunk.push(model[index])
      continue index + 1
    } nobreak {
      index
    }
    chunks.push(chunk)
    continue next
  }
  chunks
}

///|
fn deque_array_chunk_by_even_boundary(
  model : Array[Int32],
) -> Array[Array[Int32]] {
  let chunks : Array[Array[Int32]] = []
  guard model.length() > 0 else { return chunks }
  let chunk : Array[Int32] = []
  chunk.push(model[0])
  for index in 1..<model.length() {
    if (index - 1) % 2 == 0 {
      chunk.push(model[index])
    } else {
      chunks.push(chunk.copy())
      chunk.clear()
      chunk.push(model[index])
    }
  }
  chunks.push(chunk)
  chunks
}

///|
fn deque_array_flatten(nested : Array[Array[Int32]]) -> Array[Int32] {
  let flattened : Array[Int32] = []
  for values in nested {
    for value in values {
      flattened.push(value)
    }
  }
  flattened
}

///|
fn deque_array_shuffle_zero(model : Array[Int32]) -> Array[Int32] {
  let shuffled = model.copy()
  for index = shuffled.length() - 1; index > 0; {
    let value = shuffled[index]
    shuffled[index] = shuffled[0]
    shuffled[0] = value
    continue index - 1
  }
  shuffled
}

///|
fn deque_linear_rand(upper : Int32) -> Int32 {
  (upper * 123 + 456) % upper
}

///|
fn deque_array_shuffle_linear(model : Array[Int32]) -> Array[Int32] {
  let shuffled = model.copy()
  for index = shuffled.length() - 1; index > 0; {
    let swap_index = deque_linear_rand(index + 1)
    let value = shuffled[index]
    shuffled[index] = shuffled[swap_index]
    shuffled[swap_index] = value
    continue index - 1
  }
  shuffled
}

///|
fn deque_min(a : Int32, b : Int32) -> Int32 {
  if a <= b {
    a
  } else {
    b
  }
}

///|
fn deque_max(a : Int32, b : Int32) -> Int32 {
  if a >= b {
    a
  } else {
    b
  }
}

///|
fn deque_array_chunks(
  model : Array[Int32],
  size : Int32,
) -> Array[Array[Int32]] {
  let chunks : Array[Array[Int32]] = []
  for start = 0; start < model.length(); {
    let chunk : Array[Int32] = []
    let end = deque_min(start + size, model.length())
    for index in start..<end {
      chunk.push(model[index])
    }
    chunks.push(chunk)
    continue start + size
  }
  chunks
}

///|
fn deque_array_blit_to(
  source : Array[Int32],
  dst : Array[Int32],
  src_offset : Int32,
  dst_offset : Int32,
  len : Int32,
) -> Array[Int32] {
  let result = dst.copy()
  let required_len = dst_offset + len
  while result.length() < required_len {
    result.push(0)
  }
  for offset in 0..<len {
    result[dst_offset + offset] = source[src_offset + offset]
  }
  result
}

///|
fn deque_array_contains(model : Array[Int32], value : Int32) -> Bool {
  for item in model {
    if item == value {
      return true
    }
  }
  false
}

///|
fn deque_array_search(model : Array[Int32], value : Int32) -> Int32? {
  for index, item in model {
    if item == value {
      return Some(index)
    }
  }
  None
}

///|
fn deque_array_is_sorted(model : Array[Int32]) -> Bool {
  for index in 1..<model.length() {
    if model[index - 1] > model[index] {
      return false
    }
  }
  true
}

///|
fn deque_array_binary_search(
  model : Array[Int32],
  value : Int32,
) -> Result[Int32, Int32] {
  for low = 0, high = model.length(); low < high; {
    let mid = low + (high - low) / 2
    if model[mid] < value {
      continue mid + 1, high
    } else {
      continue low, mid
    }
  } nobreak {
    if low < model.length() && model[low] == value {
      Ok(low)
    } else {
      Err(low)
    }
  }
}

///|
fn deque_array_compare(left : Array[Int32], right : Array[Int32]) -> Int32 {
  let length_order = left.length().compare(right.length())
  if length_order != 0 {
    return length_order
  }
  for index in 0..<left.length() {
    let item_order = left[index].compare(right[index])
    if item_order != 0 {
      return item_order
    }
  }
  0
}

///|
fn deque_transition_values(
  model : Array[Int32],
  command : DequeCommand,
) -> Array[Int32] {
  match command {
    DequeReset(values, _)
    | DequeResetFromJson(values)
    | DequeResetWrapped(values) => values.copy()
    DequePushBack(value) => {
      let next = model.copy()
      next.push(value)
      next
    }
    DequePushFront(value) => {
      let next = model.copy()
      next.insert(0, value)
      next
    }
    DequePopBack => {
      let (_, next) = deque_array_pop_back(model)
      next
    }
    DequePopFront => {
      let (_, next) = deque_array_pop_front(model)
      next
    }
    DequeUnsafePopBack => {
      let (_, next) = deque_array_pop_back(model)
      next
    }
    DequeUnsafePopFront => {
      let (_, next) = deque_array_pop_front(model)
      next
    }
    DequeSet(index, value) => {
      let next = model.copy()
      next[index] = value
      next
    }
    DequeInsert(index, value) => {
      let next = model.copy()
      next.insert(index, value)
      next
    }
    DequeRemove(index) => {
      let next = model.copy()
      ignore(next.remove(index))
      next
    }
    DequeClear => []
    DequeTruncate(len) => {
      let next = model.copy()
      next.truncate(len)
      next
    }
    DequeDrain(start, len) => {
      let (_, kept) = deque_array_drain(model, start, len)
      kept
    }
    DequeDrainToEnd(start) => {
      let (_, kept) = deque_array_drain_to_end(model, start)
      kept
    }
    DequeRetainAtLeast(threshold) =>
      deque_array_retain_at_least(model, threshold)
    DequeRetainMapEven(delta) => deque_array_retain_map_even(model, delta)
    DequeRetainEvenIndex => deque_array_even_index(model)
    DequeRetainMapAddCallIndex => deque_array_retain_map_add_call_index(model)
    DequeExtractBelow(threshold) => {
      let (_, kept) = deque_array_extract_below(model, threshold)
      kept
    }
    DequeFilterEvenIndex => model.copy()
    DequeMapAddCallIndex => model.copy()
    DequeReverseInPlace => deque_reverse_array(model)
    DequeShuffleInPlaceZero => deque_array_shuffle_zero(model)
    DequeShuffleInPlaceLinear => deque_array_shuffle_linear(model)
    DequeAppend(values) => deque_concat(model, values)
    DequeAppendSelf => deque_concat(model, model)
    DequeAppendWrapped(values) => deque_concat(model, values)
    DequeBlitSelf(src_offset, dst_offset, len) =>
      deque_array_blit_to(model, model, src_offset, dst_offset, len)
    DequeConstruct(_, _)
    | DequeFromIter(_)
    | DequeFromJson(_)
    | DequeFilterAtLeast(_)
    | DequeMapAdd(_)
    | DequeMapiAddIndex
    | DequeChunkByNondecreasing
    | DequeChunkByEvenBoundary
    | DequeFlatten(_)
    | DequeFlattenWrapped(_)
    | DequeFlattenSlack(_)
    | DequeFlattenWrappedSlack(_)
    | DequeContains(_)
    | DequeSearch(_)
    | DequeBinarySearch(_)
    | DequeBinarySearchBy(_)
    | DequeEqual(_)
    | DequeNotEqual(_)
    | DequeCompare(_)
    | DequeLessThan(_)
    | DequeLessEqual(_)
    | DequeGreaterThan(_)
    | DequeGreaterEqual(_)
    | DequeShuffleZero
    | DequeShuffleLinear
    | DequeBlitTo(_, _, _, _)
    | DequeBlitToWrappedDst(_, _, _, _)
    | DequeChunks(_)
    | DequeFront
    | DequeBack
    | DequeGet(_)
    | DequeAt(_)
    | DequeReserveCapacity(_)
    | DequeShrinkToFit
    | DequeAdd(_)
    | DequeAddSelf
    | DequeAddWrapped(_)
    | DequeCopy
    | DequeRev
    | DequeToJson => model.copy()
  }
}

///|
fn deque_max3(a : Int32, b : Int32, c : Int32) -> Int32 {
  deque_max(deque_max(a, b), c)
}

///|
fn deque_symbolic_capacity(
  model : DequeModel,
  command : DequeCommand,
  next_values : Array[Int32],
) -> Int32 {
  match command {
    DequeReset(values, capacity) => deque_capacity_for_array(values, capacity)
    DequeResetFromJson(values) => values.length()
    DequeResetWrapped(values) => deque_max(values.length(), 1)
    DequeShrinkToFit => next_values.length()
    DequeReserveCapacity(capacity) =>
      deque_max3(model.capacity, capacity, next_values.length())
    _ => deque_max(model.capacity, next_values.length())
  }
}

///|
fn deque_transition(model : DequeModel, command : DequeCommand) -> DequeModel {
  let next_values = deque_transition_values(model.values, command)
  deque_model(
    next_values,
    capacity=deque_symbolic_capacity(model, command, next_values),
  )
}

///|
fn deque_transition_from_response(
  model : DequeModel,
  command : DequeCommand,
  response : DequeResponse,
) -> DequeModel {
  deque_model(
    deque_transition_values(model.values, command),
    capacity=response.capacity,
  )
}

///|
fn deque_capacity_for_array(values : Array[Int32], capacity : Int32) -> Int32 {
  deque_max(values.length(), capacity)
}

///|
fn deque_expected_derived(
  model : DequeModel,
  command : DequeCommand,
) -> Array[DequeExpectedObservation] {
  let values = model.values
  match command {
    DequeConstruct(values, capacity) =>
      [
        deque_expected_observation(
          values,
          exact_capacity=Some(deque_capacity_for_array(values, capacity)),
        ),
      ]
    DequeFromIter(values) =>
      [deque_expected_observation(values, capacity_min=values.length())]
    DequeFromJson(values) =>
      [deque_expected_observation(values, exact_capacity=Some(values.length()))]
    DequeDrain(start, len) => {
      let (drained, _) = deque_array_drain(values, start, len)
      [
        deque_expected_observation(
          drained,
          exact_capacity=Some(drained.length()),
        ),
      ]
    }
    DequeDrainToEnd(start) => {
      let (drained, _) = deque_array_drain_to_end(values, start)
      [
        deque_expected_observation(
          drained,
          exact_capacity=Some(drained.length()),
        ),
      ]
    }
    DequeExtractBelow(threshold) => {
      let (extracted, _) = deque_array_extract_below(values, threshold)
      [deque_expected_observation(extracted, capacity_min=extracted.length())]
    }
    DequeFilterAtLeast(threshold) =>
      [
        deque_expected_observation(
          deque_array_filter_at_least(values, threshold),
          capacity_min=deque_array_filter_at_least(values, threshold).length(),
        ),
      ]
    DequeFilterEvenIndex =>
      [
        deque_expected_observation(
          deque_array_even_index(values),
          capacity_min=deque_array_even_index(values).length(),
        ),
      ]
    DequeMapAdd(delta) =>
      [
        deque_expected_observation(
          deque_array_map_add(values, delta),
          exact_capacity=Some(values.length()),
        ),
      ]
    DequeMapAddCallIndex =>
      [
        deque_expected_observation(
          deque_array_map_add_call_index(values),
          exact_capacity=Some(values.length()),
        ),
      ]
    DequeMapiAddIndex =>
      [
        deque_expected_observation(
          deque_array_mapi_add_index(values),
          exact_capacity=Some(values.length()),
        ),
      ]
    DequeChunkByNondecreasing => {
      let expected : Array[DequeExpectedObservation] = []
      for chunk in deque_array_chunk_by_nondecreasing(values) {
        expected.push(deque_expected_observation(chunk))
      }
      expected
    }
    DequeChunkByEvenBoundary => {
      let expected : Array[DequeExpectedObservation] = []
      for chunk in deque_array_chunk_by_even_boundary(values) {
        expected.push(deque_expected_observation(chunk))
      }
      expected
    }
    DequeFlatten(nested) =>
      [
        deque_expected_observation(
          deque_array_flatten(nested),
          exact_capacity=Some(deque_array_flatten(nested).length()),
        ),
      ]
    DequeFlattenWrapped(nested)
    | DequeFlattenSlack(nested)
    | DequeFlattenWrappedSlack(nested) =>
      [
        deque_expected_observation(
          deque_array_flatten(nested),
          exact_capacity=Some(deque_array_flatten(nested).length()),
        ),
      ]
    DequeAdd(other) =>
      [
        deque_expected_observation(
          deque_concat(values, other),
          exact_capacity=Some(values.length() + other.length()),
        ),
      ]
    DequeAddSelf =>
      [
        deque_expected_observation(
          deque_concat(values, values),
          exact_capacity=Some(values.length() * 2),
        ),
      ]
    DequeAddWrapped(other) =>
      [
        deque_expected_observation(
          deque_concat(values, other),
          exact_capacity=Some(values.length() + other.length()),
        ),
      ]
    DequeCopy =>
      [deque_expected_observation(values, exact_capacity=Some(values.length()))]
    DequeRev =>
      [
        deque_expected_observation(
          deque_reverse_array(values),
          exact_capacity=Some(values.length()),
        ),
      ]
    DequeShuffleZero =>
      [
        deque_expected_observation(
          deque_array_shuffle_zero(values),
          exact_capacity=Some(values.length()),
        ),
      ]
    DequeShuffleLinear =>
      [
        deque_expected_observation(
          deque_array_shuffle_linear(values),
          exact_capacity=Some(values.length()),
        ),
      ]
    DequeBlitTo(dst, src_offset, dst_offset, len) =>
      [
        deque_expected_observation(
          deque_array_blit_to(values, dst, src_offset, dst_offset, len),
          capacity_min=dst.length(),
        ),
      ]
    DequeBlitToWrappedDst(dst, src_offset, dst_offset, len) =>
      [
        deque_expected_observation(
          deque_array_blit_to(values, dst, src_offset, dst_offset, len),
          capacity_min=dst.length(),
        ),
      ]
    DequeChunks(size) => {
      let expected : Array[DequeExpectedObservation] = []
      for chunk in deque_array_chunks(values, size) {
        expected.push(deque_expected_observation(chunk, capacity_min=size))
      }
      expected
    }
    DequeFront
    | DequeBack
    | DequeGet(_)
    | DequeAt(_)
    | DequeReset(_, _)
    | DequeResetFromJson(_)
    | DequeResetWrapped(_)
    | DequeSet(_, _)
    | DequeInsert(_, _)
    | DequeRemove(_)
    | DequeClear
    | DequeTruncate(_)
    | DequeRetainAtLeast(_)
    | DequeRetainMapEven(_)
    | DequeRetainEvenIndex
    | DequeRetainMapAddCallIndex
    | DequeReverseInPlace
    | DequeShuffleInPlaceZero
    | DequeShuffleInPlaceLinear
    | DequeReserveCapacity(_)
    | DequeShrinkToFit
    | DequeAppend(_)
    | DequeAppendSelf
    | DequeAppendWrapped(_)
    | DequeBlitSelf(_, _, _)
    | DequePushBack(_)
    | DequePushFront(_)
    | DequePopBack
    | DequePopFront
    | DequeUnsafePopBack
    | DequeUnsafePopFront
    | DequeToJson
    | DequeContains(_)
    | DequeSearch(_)
    | DequeBinarySearch(_)
    | DequeBinarySearchBy(_)
    | DequeEqual(_)
    | DequeNotEqual(_)
    | DequeLessThan(_)
    | DequeLessEqual(_)
    | DequeGreaterThan(_)
    | DequeGreaterEqual(_)
    | DequeCompare(_) => []
  }
}

///|
fn deque_expected_result(
  model : DequeModel,
  command : DequeCommand,
) -> DequeResult {
  let values = model.values
  match command {
    DequeConstruct(values, _) => DequeItems(values.copy())
    DequeFromIter(values) => DequeItems(values.copy())
    DequeFromJson(values) => DequeItems(values.copy())
    DequeReset(_, _) | DequeResetFromJson(_) | DequeResetWrapped(_) => DequeDone
    DequePopBack => {
      let (value, _) = deque_array_pop_back(values)
      DequeOptional(value)
    }
    DequePopFront => {
      let (value, _) = deque_array_pop_front(values)
      DequeOptional(value)
    }
    DequeUnsafePopBack | DequeUnsafePopFront => DequeDone
    DequeFront => DequeOptional(deque_front_model(values))
    DequeBack => DequeOptional(deque_back_model(values))
    DequeGet(index) => DequeOptional(deque_get_model(values, index))
    DequeAt(index) => DequeItem(values[index])
    DequeRemove(index) => DequeItem(values[index])
    DequeDrain(start, len) => {
      let (drained, _) = deque_array_drain(values, start, len)
      DequeItems(drained)
    }
    DequeDrainToEnd(start) => {
      let (drained, _) = deque_array_drain_to_end(values, start)
      DequeItems(drained)
    }
    DequeExtractBelow(threshold) => {
      let (extracted, _) = deque_array_extract_below(values, threshold)
      DequeItems(extracted)
    }
    DequeFilterAtLeast(threshold) =>
      DequeItems(deque_array_filter_at_least(values, threshold))
    DequeFilterEvenIndex => DequeItems(deque_array_even_index(values))
    DequeMapAdd(delta) => DequeItems(deque_array_map_add(values, delta))
    DequeMapAddCallIndex => DequeItems(deque_array_map_add_call_index(values))
    DequeMapiAddIndex => DequeItems(deque_array_mapi_add_index(values))
    DequeChunkByNondecreasing =>
      DequeNestedItems(deque_array_chunk_by_nondecreasing(values))
    DequeChunkByEvenBoundary =>
      DequeNestedItems(deque_array_chunk_by_even_boundary(values))
    DequeFlatten(nested) => DequeItems(deque_array_flatten(nested))
    DequeFlattenWrapped(nested)
    | DequeFlattenSlack(nested)
    | DequeFlattenWrappedSlack(nested) =>
      DequeItems(deque_array_flatten(nested))
    DequeAdd(other) => DequeItems(deque_concat(values, other))
    DequeAddSelf => DequeItems(deque_concat(values, values))
    DequeAddWrapped(other) => DequeItems(deque_concat(values, other))
    DequeCopy => DequeItems(values.copy())
    DequeRev => DequeItems(deque_reverse_array(values))
    DequeToJson => DequeBool(true)
    DequeContains(value) => DequeBool(deque_array_contains(values, value))
    DequeSearch(value) => DequeOptional(deque_array_search(values, value))
    DequeBinarySearch(value) =>
      DequeSearchResult(deque_array_binary_search(values, value))
    DequeBinarySearchBy(value) =>
      DequeSearchResult(deque_array_binary_search(values, value))
    DequeEqual(other) => DequeBool(values == other)
    DequeNotEqual(other) => DequeBool(values != other)
    DequeCompare(other) => DequeInt(deque_array_compare(values, other))
    DequeLessThan(other) => DequeBool(deque_array_compare(values, other) < 0)
    DequeLessEqual(other) => DequeBool(deque_array_compare(values, other) <= 0)
    DequeGreaterThan(other) => DequeBool(deque_array_compare(values, other) > 0)
    DequeGreaterEqual(other) =>
      DequeBool(deque_array_compare(values, other) >= 0)
    DequeShuffleZero => DequeItems(deque_array_shuffle_zero(values))
    DequeShuffleLinear => DequeItems(deque_array_shuffle_linear(values))
    DequeBlitTo(dst, src_offset, dst_offset, len) =>
      DequeItems(deque_array_blit_to(values, dst, src_offset, dst_offset, len))
    DequeBlitToWrappedDst(dst, src_offset, dst_offset, len) =>
      DequeItems(deque_array_blit_to(values, dst, src_offset, dst_offset, len))
    DequeChunks(size) => DequeNestedItems(deque_array_chunks(values, size))
    DequePushBack(_)
    | DequePushFront(_)
    | DequeSet(_, _)
    | DequeInsert(_, _)
    | DequeClear
    | DequeTruncate(_)
    | DequeRetainAtLeast(_)
    | DequeRetainMapEven(_)
    | DequeRetainEvenIndex
    | DequeRetainMapAddCallIndex
    | DequeReverseInPlace
    | DequeShuffleInPlaceZero
    | DequeShuffleInPlaceLinear
    | DequeReserveCapacity(_)
    | DequeShrinkToFit
    | DequeAppend(_)
    | DequeAppendSelf
    | DequeAppendWrapped(_)
    | DequeBlitSelf(_, _, _) => DequeDone
  }
}

///|
fn deque_expected_response(
  model : DequeModel,
  command : DequeCommand,
) -> DequeResponse {
  deque_model_response(
    deque_expected_result(model, command),
    deque_transition(model, command),
    derived=[],
  )
}

///|
fn deque_zero_rand(_upper : Int32) -> Int32 {
  0
}

///|
fn run_deque_command(
  command : DequeCommand,
  system : DequeSystem,
) -> DequeResponse raise {
  let deque = system.deque
  let (result, derived) = match command {
    DequeConstruct(values, capacity) => {
      let constructed = @deque.Deque(values, capacity~)
      (DequeItems(constructed.to_array()), [deque_observation(constructed)])
    }
    DequeFromIter(values) => {
      let constructed = @deque.from_iter(values.iter())
      (DequeItems(constructed.to_array()), [deque_observation(constructed)])
    }
    DequeFromJson(values) => {
      let constructed : @deque.Deque[Int32] = @json.from_json(Json(values))
      (DequeItems(constructed.to_array()), [deque_observation(constructed)])
    }
    DequeReset(values, capacity) => {
      system.deque = @deque.Deque(values, capacity~)
      (DequeDone, [])
    }
    DequeResetFromJson(values) => {
      system.deque = @json.from_json(Json(values))
      (DequeDone, [])
    }
    DequeResetWrapped(values) => {
      system.deque = deque_wrapped_from_array(values)
      (DequeDone, [])
    }
    DequePushBack(value) => {
      deque.push_back(value)
      (DequeDone, [])
    }
    DequePushFront(value) => {
      deque.push_front(value)
      (DequeDone, [])
    }
    DequePopBack => (DequeOptional(deque.pop_back()), [])
    DequePopFront => (DequeOptional(deque.pop_front()), [])
    DequeUnsafePopBack => {
      deque.unsafe_pop_back()
      (DequeDone, [])
    }
    DequeUnsafePopFront => {
      deque.unsafe_pop_front()
      (DequeDone, [])
    }
    DequeFront => (DequeOptional(deque.front()), [])
    DequeBack => (DequeOptional(deque.back()), [])
    DequeGet(index) => (DequeOptional(deque.get(index)), [])
    DequeAt(index) => (DequeItem(deque[index]), [])
    DequeSet(index, value) => {
      deque[index] = value
      (DequeDone, [])
    }
    DequeInsert(index, value) => {
      deque.insert(index, value)
      (DequeDone, [])
    }
    DequeRemove(index) => (DequeItem(deque.remove(index)), [])
    DequeClear => {
      deque.clear()
      (DequeDone, [])
    }
    DequeTruncate(len) => {
      deque.truncate(len)
      (DequeDone, [])
    }
    DequeDrain(start, len) => {
      let drained = deque.drain(start~, len~)
      (DequeItems(drained.to_array()), [deque_observation(drained)])
    }
    DequeDrainToEnd(start) => {
      let drained = deque.drain(start~)
      (DequeItems(drained.to_array()), [deque_observation(drained)])
    }
    DequeRetainAtLeast(threshold) => {
      deque.retain(value => value >= threshold)
      (DequeDone, [])
    }
    DequeRetainMapEven(delta) => {
      deque.retain_map(value => deque_retain_map_even_value(value, delta))
      (DequeDone, [])
    }
    DequeRetainEvenIndex => {
      let mut index = 0
      deque.retain(_value => {
        let keep = index % 2 == 0
        index += 1
        keep
      })
      (DequeDone, [])
    }
    DequeRetainMapAddCallIndex => {
      let mut index = 0
      deque.retain_map(value => {
        let current = index
        index += 1
        if current % 2 == 0 {
          Some(value + current)
        } else {
          None
        }
      })
      (DequeDone, [])
    }
    DequeExtractBelow(threshold) => {
      let extracted = deque.extract_if(value => value < threshold)
      (DequeItems(extracted.to_array()), [deque_observation(extracted)])
    }
    DequeFilterAtLeast(threshold) => {
      let filtered = deque.filter(value => value >= threshold)
      (DequeItems(filtered.to_array()), [deque_observation(filtered)])
    }
    DequeFilterEvenIndex => {
      let mut index = 0
      let filtered = deque.filter(_value => {
        let keep = index % 2 == 0
        index += 1
        keep
      })
      (DequeItems(filtered.to_array()), [deque_observation(filtered)])
    }
    DequeMapAdd(delta) => {
      let mapped = deque.map(value => value + delta)
      (DequeItems(mapped.to_array()), [deque_observation(mapped)])
    }
    DequeMapAddCallIndex => {
      let mut index = 0
      let mapped = deque.map(value => {
        let current = index
        index += 1
        value + current
      })
      (DequeItems(mapped.to_array()), [deque_observation(mapped)])
    }
    DequeMapiAddIndex => {
      let mapped = deque.mapi((index, value) => value + index)
      (DequeItems(mapped.to_array()), [deque_observation(mapped)])
    }
    DequeChunkByNondecreasing => {
      let chunks = deque.chunk_by((left, right) => left <= right)
      let items : Array[Array[Int32]] = []
      let observations : Array[DequeObservation] = []
      chunks.each(chunk => {
        items.push(chunk.to_array())
        observations.push(deque_observation(chunk))
      })
      (DequeNestedItems(items), observations)
    }
    DequeChunkByEvenBoundary => {
      let mut boundary = 0
      let chunks = deque.chunk_by((_left, _right) => {
        let keep = boundary % 2 == 0
        boundary += 1
        keep
      })
      let items : Array[Array[Int32]] = []
      let observations : Array[DequeObservation] = []
      chunks.each(chunk => {
        items.push(chunk.to_array())
        observations.push(deque_observation(chunk))
      })
      (DequeNestedItems(items), observations)
    }
    DequeFlatten(nested) => {
      let deques : Array[@deque.Deque[Int32]] = []
      for values in nested {
        deques.push(@deque.from_array(values))
      }
      let flattened = @deque.from_array(deques).flatten()
      (DequeItems(flattened.to_array()), [deque_observation(flattened)])
    }
    DequeFlattenWrapped(nested) => {
      let deques : Array[@deque.Deque[Int32]] = []
      for values in nested {
        deques.push(deque_wrapped_from_array(values))
      }
      let flattened = @deque.from_array(deques).flatten()
      (DequeItems(flattened.to_array()), [deque_observation(flattened)])
    }
    DequeFlattenSlack(nested) => {
      let deques : Array[@deque.Deque[Int32]] = []
      for values in nested {
        deques.push(deque_slack_from_array(values, wrapped=false))
      }
      let flattened = @deque.from_array(deques).flatten()
      (DequeItems(flattened.to_array()), [deque_observation(flattened)])
    }
    DequeFlattenWrappedSlack(nested) => {
      let deques : Array[@deque.Deque[Int32]] = []
      for values in nested {
        deques.push(deque_slack_from_array(values, wrapped=true))
      }
      let flattened = deque_outer_wrapped_from_deques(deques).flatten()
      (DequeItems(flattened.to_array()), [deque_observation(flattened)])
    }
    DequeReverseInPlace => {
      deque.rev_in_place()
      (DequeDone, [])
    }
    DequeReserveCapacity(capacity) => {
      deque.reserve_capacity(capacity)
      (DequeDone, [])
    }
    DequeShrinkToFit => {
      deque.shrink_to_fit()
      (DequeDone, [])
    }
    DequeAppend(values) => {
      deque.append(@deque.from_array(values))
      (DequeDone, [])
    }
    DequeAppendSelf => {
      deque.append(deque)
      (DequeDone, [])
    }
    DequeAppendWrapped(values) => {
      deque.append(deque_wrapped_from_array(values))
      (DequeDone, [])
    }
    DequeAdd(values) => {
      let added = deque + @deque.from_array(values)
      (DequeItems(added.to_array()), [deque_observation(added)])
    }
    DequeAddSelf => {
      let added = deque + deque
      (DequeItems(added.to_array()), [deque_observation(added)])
    }
    DequeAddWrapped(values) => {
      let added = deque + deque_wrapped_from_array(values)
      (DequeItems(added.to_array()), [deque_observation(added)])
    }
    DequeCopy => {
      let copied = deque.copy()
      (DequeItems(copied.to_array()), [deque_observation(copied)])
    }
    DequeRev => {
      let reversed = deque.rev()
      (DequeItems(reversed.to_array()), [deque_observation(reversed)])
    }
    DequeToJson =>
      (DequeBool(@json.to_json(deque) == Json(deque.to_array())), [])
    DequeContains(value) => (DequeBool(deque.contains(value)), [])
    DequeSearch(value) => (DequeOptional(deque.search(value)), [])
    DequeBinarySearch(value) =>
      (DequeSearchResult(deque.binary_search(value)), [])
    DequeBinarySearchBy(value) =>
      (
        DequeSearchResult(deque.binary_search_by(item => item.compare(value))),
        [],
      )
    DequeEqual(other) => (DequeBool(deque == @deque.from_array(other)), [])
    DequeNotEqual(other) => (DequeBool(deque != @deque.from_array(other)), [])
    DequeCompare(other) =>
      (DequeInt(deque.compare(@deque.from_array(other))), [])
    DequeLessThan(other) => (DequeBool(deque < @deque.from_array(other)), [])
    DequeLessEqual(other) => (DequeBool(deque <= @deque.from_array(other)), [])
    DequeGreaterThan(other) => (DequeBool(deque > @deque.from_array(other)), [])
    DequeGreaterEqual(other) =>
      (DequeBool(deque >= @deque.from_array(other)), [])
    DequeShuffleZero => {
      let shuffled = deque.shuffle(rand=deque_zero_rand)
      (DequeItems(shuffled.to_array()), [deque_observation(shuffled)])
    }
    DequeShuffleInPlaceZero => {
      deque.shuffle_in_place(rand=deque_zero_rand)
      (DequeDone, [])
    }
    DequeShuffleLinear => {
      let shuffled = deque.shuffle(rand=deque_linear_rand)
      (DequeItems(shuffled.to_array()), [deque_observation(shuffled)])
    }
    DequeShuffleInPlaceLinear => {
      deque.shuffle_in_place(rand=deque_linear_rand)
      (DequeDone, [])
    }
    DequeBlitTo(dst, src_offset, dst_offset, len) => {
      let target = @deque.from_array(dst)
      deque.blit_to(target, src_offset~, dst_offset~, len~)
      (DequeItems(target.to_array()), [deque_observation(target)])
    }
    DequeBlitToWrappedDst(dst, src_offset, dst_offset, len) => {
      let target = deque_wrapped_from_array(dst)
      deque.blit_to(target, src_offset~, dst_offset~, len~)
      (DequeItems(target.to_array()), [deque_observation(target)])
    }
    DequeBlitSelf(src_offset, dst_offset, len) => {
      deque.blit_to(deque, src_offset~, dst_offset~, len~)
      (DequeDone, [])
    }
    DequeChunks(size) => {
      let chunks = deque.chunks(size)
      let items : Array[Array[Int32]] = []
      let observations : Array[DequeObservation] = []
      chunks.each(chunk => {
        items.push(chunk.to_array())
        observations.push(deque_observation(chunk))
      })
      (DequeNestedItems(items), observations)
    }
  }
  deque_snapshot(result, system.deque, derived~)
}

///|
// Deque precondition:
// This function describes the legal client-side domain for each generated
// command before it is executed against either the Array model or the real
// deque. Commands not listed here are total for every model state used by this
// test, so they remain valid even when the deque is empty.
//
// The checks intentionally mirror the standard-library API contracts rather
// than the generator's current shape. That keeps shrinking and scripted replay
// honest: if a shrinker creates an out-of-domain command, replay rejects it here
// instead of letting the command trap while running the system under test.
fn deque_precondition(
  model : DequeModel,
  command : DequeCommand,
) -> @quickcheck_statemachine.Logic {
  let len = model.values.length()
  let ok = match command {
    // Direct indexing APIs require an existing element. This covers both
    // read-only indexing and mutating/removing by index.
    DequeUnsafePopBack | DequeUnsafePopFront => len > 0
    DequeAt(index) | DequeSet(index, _) | DequeRemove(index) =>
      0 <= index && index < len
    // Insertion may target the one-past-the-end position, matching Array and
    // deque insertion semantics.
    DequeInsert(index, _) => 0 <= index && index <= len
    // Drain is represented as a start plus length. Both must be non-negative,
    // the start may be exactly at the end only for an empty drain, and the
    // selected range must stay inside the current logical contents.
    DequeDrain(start, drain_len) =>
      0 <= start && 0 <= drain_len && start <= len && start + drain_len <= len
    // The omitted `len` form drains from `start` through the end.
    DequeDrainToEnd(start) => 0 <= start && start <= len
    // Reserving capacity is valid for zero or positive requests only.
    DequeReserveCapacity(capacity) => capacity >= 0
    // Binary search is specified only for sorted input. The generator usually
    // respects this, but the precondition also protects shrinks and scripts.
    DequeBinarySearch(_) | DequeBinarySearchBy(_) =>
      deque_array_is_sorted(model.values)
    // blit_to copies from the deque into a destination deque. The source range
    // must fit the current deque and the destination offset must name an
    // existing insertion/copy boundary; the destination can grow during the
    // modelled copy, so we do not require dst_offset + blit_len <= dst.length().
    DequeBlitTo(dst, src_offset, dst_offset, blit_len) =>
      0 <= src_offset &&
      0 <= dst_offset &&
      0 <= blit_len &&
      src_offset + blit_len <= len &&
      dst_offset <= dst.length()
    DequeBlitToWrappedDst(dst, src_offset, dst_offset, blit_len) =>
      0 <= src_offset &&
      0 <= dst_offset &&
      0 <= blit_len &&
      src_offset + blit_len <= len &&
      dst_offset <= dst.length()
    DequeBlitSelf(src_offset, dst_offset, blit_len) =>
      0 <= src_offset &&
      0 <= dst_offset &&
      0 <= blit_len &&
      src_offset + blit_len <= len &&
      dst_offset <= len
    // Chunk size zero would make iteration undefined/non-progressing.
    DequeChunks(size) => size > 0
    // Everything else is total for the tested API surface: pop/front/back/get
    // report optional results on empty or out-of-range access, truncate clamps or
    // no-ops for boundary lengths, and clear/filter/map/copy/search-style
    // commands are valid for any current contents.
    _ => true
  }
  @quickcheck_statemachine.Logic::predicate(
    name="deque command precondition",
    value=ok,
  )
}

///|
// Deque postcondition:
// The command runner returns a rich `DequeResponse`: the direct API result, a
// snapshot of the mutated deque, and observations of any derived deque produced
// by APIs such as `map`, `filter`, `copy`, `drain`, or `chunks`. The
// postcondition checks all of those surfaces against a pure Array model.
//
// The model is deliberately stricter than a simple `to_array` comparison. It
// verifies every observation channel that should present the same logical order:
// length/emptiness, front/back, forward and reverse iterators, callbacks,
// indexed access, view flattening, and capacity invariants.
fn deque_postcondition(
  model : DequeModel,
  command : DequeCommand,
  response : DequeResponse,
) -> @quickcheck_statemachine.Logic {
  // `next` is the Array model after the command. All observable contents below
  // are derived from this single value so the expected result, mutated snapshot,
  // and iterator/view checks cannot drift apart.
  let next = deque_transition_values(model.values, command)
  let expected_result = deque_expected_result(model, command)
  let expected_front = deque_front_model(next)
  let expected_back = deque_back_model(next)
  let expected_reversed = deque_reverse_array(next)
  let expected_indexed = deque_indexed_model(next)
  let expected_rev_indexed = deque_indexed_model(expected_reversed)
  // Capacity is intentionally modelled command-by-command because deque APIs
  // have different allocation promises:
  //
  // * reserve_capacity may grow, but cannot shrink below the previous capacity
  //   or the requested capacity;
  // * shrink_to_fit should make capacity exactly match length;
  // * removals and in-place filtering/reversal should preserve existing storage;
  // * derived/non-mutating APIs should leave the original deque capacity alone;
  // * push/insert/append may allocate, but must not report less capacity than
  //   before the operation.
  let capacity_command_ok = match command {
    DequeReset(values, capacity) =>
      response.capacity == deque_capacity_for_array(values, capacity)
    DequeResetFromJson(values) => response.capacity == values.length()
    DequeResetWrapped(values) =>
      response.capacity == deque_max(values.length(), 1)
    DequeReserveCapacity(capacity) =>
      response.capacity >= capacity && response.capacity >= model.capacity
    DequeShrinkToFit => response.capacity == next.length()
    DequePopBack
    | DequePopFront
    | DequeUnsafePopBack
    | DequeUnsafePopFront
    | DequeSet(_, _)
    | DequeRemove(_)
    | DequeClear
    | DequeTruncate(_)
    | DequeDrain(_, _)
    | DequeDrainToEnd(_)
    | DequeRetainAtLeast(_)
    | DequeRetainMapEven(_)
    | DequeRetainEvenIndex
    | DequeRetainMapAddCallIndex
    | DequeExtractBelow(_)
    | DequeReverseInPlace
    | DequeShuffleInPlaceZero
    | DequeShuffleInPlaceLinear => response.capacity == model.capacity
    DequeConstruct(_, _)
    | DequeFromIter(_)
    | DequeFromJson(_)
    | DequeFront
    | DequeBack
    | DequeGet(_)
    | DequeAt(_)
    | DequeFilterAtLeast(_)
    | DequeFilterEvenIndex
    | DequeMapAdd(_)
    | DequeMapAddCallIndex
    | DequeMapiAddIndex
    | DequeChunkByNondecreasing
    | DequeChunkByEvenBoundary
    | DequeFlatten(_)
    | DequeFlattenWrapped(_)
    | DequeFlattenSlack(_)
    | DequeFlattenWrappedSlack(_)
    | DequeAdd(_)
    | DequeAddSelf
    | DequeAddWrapped(_)
    | DequeCopy
    | DequeRev
    | DequeToJson
    | DequeContains(_)
    | DequeSearch(_)
    | DequeBinarySearch(_)
    | DequeBinarySearchBy(_)
    | DequeEqual(_)
    | DequeNotEqual(_)
    | DequeCompare(_)
    | DequeLessThan(_)
    | DequeLessEqual(_)
    | DequeGreaterThan(_)
    | DequeGreaterEqual(_)
    | DequeShuffleZero
    | DequeShuffleLinear
    | DequeBlitTo(_, _, _, _)
    | DequeBlitToWrappedDst(_, _, _, _)
    | DequeChunks(_) => response.capacity == model.capacity
    DequePushBack(_)
    | DequePushFront(_)
    | DequeInsert(_, _)
    | DequeAppend(_)
    | DequeAppendSelf
    | DequeAppendWrapped(_)
    | DequeBlitSelf(_, _, _) => response.capacity >= model.capacity
  }
  // Derived deques are returned by APIs that allocate or expose another deque
  // value. They are checked independently because the original deque may be
  // unchanged while the returned deque has its own contents and capacity.
  let expected_derived = deque_expected_derived(model, command)
  let derived_ok = deque_observations_match(response.derived, expected_derived)
  // A few derived results have exact capacity guarantees in addition to the
  // general observation checks. Keep those assertions separate so failures point
  // at the capacity promise rather than at the broad snapshot comparison.
  let result_capacity_ok = match command {
    DequeConstruct(values, capacity) =>
      expected_derived.length() == 1 &&
      response.derived[0].capacity == deque_capacity_for_array(values, capacity)
    DequeFromJson(values) =>
      expected_derived.length() == 1 &&
      response.derived[0].capacity == values.length()
    DequeCopy | DequeRev =>
      expected_derived.length() == 1 &&
      response.derived[0].capacity == next.length()
    _ => true
  }
  // Every concrete deque must at least be able to hold its logical contents;
  // `capacity_command_ok` layers the per-command allocation promise on top.
  let capacity_ok = response.capacity >= next.length() && capacity_command_ok
  // Final lockstep comparison: the direct result must match the Array model,
  // every observation of the mutated deque must describe `next`, and every
  // derived deque must match its own expected observation.
  let ok = response.result == expected_result &&
    response.contents == next &&
    response.length == next.length() &&
    response.is_empty == (next.length() == 0) &&
    response.front == expected_front &&
    response.back == expected_back &&
    response.iter_contents == next &&
    response.rev_iter_contents == expected_reversed &&
    response.each_contents == next &&
    response.rev_each_contents == expected_reversed &&
    response.eachi_contents == expected_indexed &&
    response.iter2_contents == expected_indexed &&
    response.rev_eachi_contents == expected_rev_indexed &&
    response.rev_iter2_contents == expected_rev_indexed &&
    response.get_contents == deque_get_all_from_model(next) &&
    response.at_contents == next &&
    response.view_contents == next &&
    capacity_ok &&
    derived_ok &&
    result_capacity_ok
  @quickcheck_statemachine.Logic::predicate(
    name="deque response and snapshot match array model",
    value=ok,
  )
}

///|
fn deque_command_name(command : DequeCommand) -> String {
  match command {
    DequeConstruct(_, _) => "construct"
    DequeFromIter(_) => "from_iter"
    DequeFromJson(_) => "from_json"
    DequeReset(_, _) => "reset"
    DequeResetFromJson(_) => "reset_from_json"
    DequeResetWrapped(_) => "reset_wrapped"
    DequePushBack(_) => "push_back"
    DequePushFront(_) => "push_front"
    DequePopBack => "pop_back"
    DequePopFront => "pop_front"
    DequeUnsafePopBack => "unsafe_pop_back"
    DequeUnsafePopFront => "unsafe_pop_front"
    DequeFront => "front"
    DequeBack => "back"
    DequeGet(_) => "get"
    DequeAt(_) => "at"
    DequeSet(_, _) => "set"
    DequeInsert(_, _) => "insert"
    DequeRemove(_) => "remove"
    DequeClear => "clear"
    DequeTruncate(_) => "truncate"
    DequeDrain(_, _) => "drain"
    DequeDrainToEnd(_) => "drain_to_end"
    DequeRetainAtLeast(_) => "retain"
    DequeRetainMapEven(_) => "retain_map"
    DequeRetainEvenIndex => "retain_even_index"
    DequeRetainMapAddCallIndex => "retain_map_call_index"
    DequeExtractBelow(_) => "extract_if"
    DequeFilterAtLeast(_) => "filter"
    DequeFilterEvenIndex => "filter_even_index"
    DequeMapAdd(_) => "map"
    DequeMapAddCallIndex => "map_call_index"
    DequeMapiAddIndex => "mapi"
    DequeChunkByNondecreasing => "chunk_by"
    DequeChunkByEvenBoundary => "chunk_by_even_boundary"
    DequeFlatten(_) => "flatten"
    DequeFlattenWrapped(_) => "flatten_wrapped"
    DequeFlattenSlack(_) => "flatten_slack"
    DequeFlattenWrappedSlack(_) => "flatten_wrapped_slack"
    DequeReverseInPlace => "rev_in_place"
    DequeReserveCapacity(_) => "reserve_capacity"
    DequeShrinkToFit => "shrink_to_fit"
    DequeAppend(_) => "append"
    DequeAppendSelf => "append_self"
    DequeAppendWrapped(_) => "append_wrapped"
    DequeAdd(_) => "add"
    DequeAddSelf => "add_self"
    DequeAddWrapped(_) => "add_wrapped"
    DequeCopy => "copy"
    DequeRev => "rev"
    DequeToJson => "to_json"
    DequeContains(_) => "contains"
    DequeSearch(_) => "search"
    DequeBinarySearch(_) => "binary_search"
    DequeBinarySearchBy(_) => "binary_search_by"
    DequeEqual(_) => "equal"
    DequeNotEqual(_) => "not_equal"
    DequeCompare(_) => "compare"
    DequeLessThan(_) => "less_than"
    DequeLessEqual(_) => "less_equal"
    DequeGreaterThan(_) => "greater_than"
    DequeGreaterEqual(_) => "greater_equal"
    DequeShuffleZero => "shuffle"
    DequeShuffleInPlaceZero => "shuffle_in_place"
    DequeShuffleLinear => "shuffle_linear"
    DequeShuffleInPlaceLinear => "shuffle_in_place_linear"
    DequeBlitTo(_, _, _, _) => "blit_to"
    DequeBlitToWrappedDst(_, _, _, _) => "blit_to_wrapped_dst"
    DequeBlitSelf(_, _, _) => "blit_self"
    DequeChunks(_) => "chunks"
  }
}

///|
fn deque_reify_command(
  command : DequeCommand,
  environment : @quickcheck_statemachine.Environment[Unit],
) -> Result[DequeCommand, @quickcheck_statemachine.EnvError] {
  ignore(environment)
  Ok(command)
}

///|
fn deque_bind_response(
  symbolic : DequeResponse,
  concrete : DequeResponse,
  environment : @quickcheck_statemachine.Environment[Unit],
) -> Result[
  @quickcheck_statemachine.Environment[Unit],
  @quickcheck_statemachine.BindError,
] {
  ignore(symbolic)
  ignore(concrete)
  Ok(environment)
}

///|
fn deque_shrink_int(value : Int32) -> Array[Int32] {
  if value == 0 {
    []
  } else {
    [0, value / 2]
  }
}

///|
fn deque_shrink_values(values : Array[Int32]) -> Array[Array[Int32]] {
  if values.length() == 0 {
    []
  } else {
    let empty : Array[Int32] = []
    let first_half : Array[Int32] = []
    for index in 0..<(values.length() / 2) {
      first_half.push(values[index])
    }
    [empty, first_half]
  }
}

///|
fn deque_shrinker(
  _model : DequeModel,
  command : DequeCommand,
) -> Array[DequeCommand] {
  match command {
    DequePushBack(value) =>
      deque_shrink_int(value).map(value => DequePushBack(value))
    DequePushFront(value) =>
      deque_shrink_int(value).map(value => DequePushFront(value))
    DequeConstruct(values, capacity) => {
      let shrunk_values = deque_shrink_values(values).map(values => {
        DequeConstruct(values, capacity)
      })
      let shrunk_capacity = deque_shrink_int(capacity).map(capacity => {
        DequeConstruct(values, capacity)
      })
      deque_concat(shrunk_values, shrunk_capacity)
    }
    DequeFromIter(values) =>
      deque_shrink_values(values).map(values => DequeFromIter(values))
    DequeFromJson(values) =>
      deque_shrink_values(values).map(values => DequeFromJson(values))
    DequeReset(values, capacity) => {
      let shrunk_values = deque_shrink_values(values).map(values => {
        DequeReset(values, capacity)
      })
      let shrunk_capacity = deque_shrink_int(capacity).map(capacity => {
        DequeReset(values, capacity)
      })
      deque_concat(shrunk_values, shrunk_capacity)
    }
    DequeResetFromJson(values) =>
      deque_shrink_values(values).map(values => DequeResetFromJson(values))
    DequeResetWrapped(values) =>
      deque_shrink_values(values).map(values => DequeResetWrapped(values))
    DequeGet(index) => deque_shrink_int(index).map(index => DequeGet(index))
    DequeAt(index) => deque_shrink_int(index).map(index => DequeAt(index))
    DequeSet(index, value) => [DequeSet(0, value), DequeSet(index, 0)]
    DequeInsert(index, value) => [DequeInsert(0, value), DequeInsert(index, 0)]
    DequeRemove(index) =>
      deque_shrink_int(index).map(index => DequeRemove(index))
    DequeTruncate(len) => deque_shrink_int(len).map(len => DequeTruncate(len))
    DequeDrain(start, len) => [DequeDrain(0, len), DequeDrain(start, 0)]
    DequeDrainToEnd(start) =>
      deque_shrink_int(start).map(start => DequeDrainToEnd(start))
    DequeRetainAtLeast(threshold) =>
      deque_shrink_int(threshold).map(threshold => DequeRetainAtLeast(threshold))
    DequeRetainMapEven(delta) =>
      deque_shrink_int(delta).map(delta => DequeRetainMapEven(delta))
    DequeExtractBelow(threshold) =>
      deque_shrink_int(threshold).map(threshold => DequeExtractBelow(threshold))
    DequeFilterAtLeast(threshold) =>
      deque_shrink_int(threshold).map(threshold => DequeFilterAtLeast(threshold))
    DequeMapAdd(delta) =>
      deque_shrink_int(delta).map(delta => DequeMapAdd(delta))
    DequeFlatten(nested) =>
      if nested.length() == 0 {
        []
      } else {
        [DequeFlatten([])]
      }
    DequeFlattenWrapped(nested) =>
      if nested.length() == 0 {
        []
      } else {
        [DequeFlattenWrapped([])]
      }
    DequeFlattenSlack(nested) =>
      if nested.length() == 0 {
        []
      } else {
        [DequeFlattenSlack([])]
      }
    DequeFlattenWrappedSlack(nested) =>
      if nested.length() == 0 {
        []
      } else {
        [DequeFlattenWrappedSlack([])]
      }
    DequeReserveCapacity(capacity) =>
      deque_shrink_int(capacity).map(capacity => DequeReserveCapacity(capacity))
    DequeAppend(values) =>
      deque_shrink_values(values).map(values => DequeAppend(values))
    DequeAppendSelf => []
    DequeAppendWrapped(values) =>
      deque_shrink_values(values).map(values => DequeAppendWrapped(values))
    DequeAdd(values) =>
      deque_shrink_values(values).map(values => DequeAdd(values))
    DequeAddWrapped(values) =>
      deque_shrink_values(values).map(values => DequeAddWrapped(values))
    DequeContains(value) =>
      deque_shrink_int(value).map(value => DequeContains(value))
    DequeSearch(value) =>
      deque_shrink_int(value).map(value => DequeSearch(value))
    DequeBinarySearch(value) =>
      deque_shrink_int(value).map(value => DequeBinarySearch(value))
    DequeBinarySearchBy(value) =>
      deque_shrink_int(value).map(value => DequeBinarySearchBy(value))
    DequeEqual(values) =>
      deque_shrink_values(values).map(values => DequeEqual(values))
    DequeNotEqual(values) =>
      deque_shrink_values(values).map(values => DequeNotEqual(values))
    DequeCompare(values) =>
      deque_shrink_values(values).map(values => DequeCompare(values))
    DequeLessThan(values) =>
      deque_shrink_values(values).map(values => DequeLessThan(values))
    DequeLessEqual(values) =>
      deque_shrink_values(values).map(values => DequeLessEqual(values))
    DequeGreaterThan(values) =>
      deque_shrink_values(values).map(values => DequeGreaterThan(values))
    DequeGreaterEqual(values) =>
      deque_shrink_values(values).map(values => DequeGreaterEqual(values))
    DequeBlitTo(dst, src_offset, dst_offset, len) => {
      let shrunk_dst = deque_shrink_values(dst).map(dst => {
        DequeBlitTo(dst, src_offset, dst_offset, len)
      })
      let shrunk_src = deque_shrink_int(src_offset).map(src_offset => {
        DequeBlitTo(dst, src_offset, dst_offset, len)
      })
      let shrunk_dst_offset = deque_shrink_int(dst_offset).map(dst_offset => {
        DequeBlitTo(dst, src_offset, dst_offset, len)
      })
      let shrunk_len = deque_shrink_int(len).map(len => {
        DequeBlitTo(dst, src_offset, dst_offset, len)
      })
      deque_concat(
        deque_concat(shrunk_dst, shrunk_src),
        deque_concat(shrunk_dst_offset, shrunk_len),
      )
    }
    DequeBlitToWrappedDst(dst, src_offset, dst_offset, len) => {
      let shrunk_dst = deque_shrink_values(dst).map(dst => {
        DequeBlitToWrappedDst(dst, src_offset, dst_offset, len)
      })
      let shrunk_src = deque_shrink_int(src_offset).map(src_offset => {
        DequeBlitToWrappedDst(dst, src_offset, dst_offset, len)
      })
      let shrunk_dst_offset = deque_shrink_int(dst_offset).map(dst_offset => {
        DequeBlitToWrappedDst(dst, src_offset, dst_offset, len)
      })
      let shrunk_len = deque_shrink_int(len).map(len => {
        DequeBlitToWrappedDst(dst, src_offset, dst_offset, len)
      })
      deque_concat(
        deque_concat(shrunk_dst, shrunk_src),
        deque_concat(shrunk_dst_offset, shrunk_len),
      )
    }
    DequeBlitSelf(src_offset, dst_offset, len) => {
      let shrunk_src = deque_shrink_int(src_offset).map(src_offset => {
        DequeBlitSelf(src_offset, dst_offset, len)
      })
      let shrunk_dst_offset = deque_shrink_int(dst_offset).map(dst_offset => {
        DequeBlitSelf(src_offset, dst_offset, len)
      })
      let shrunk_len = deque_shrink_int(len).map(len => {
        DequeBlitSelf(src_offset, dst_offset, len)
      })
      deque_concat(shrunk_src, deque_concat(shrunk_dst_offset, shrunk_len))
    }
    DequeChunks(size) => deque_shrink_int(size).map(size => DequeChunks(size))
    DequePopBack
    | DequePopFront
    | DequeUnsafePopBack
    | DequeUnsafePopFront
    | DequeFront
    | DequeBack
    | DequeClear
    | DequeRetainEvenIndex
    | DequeRetainMapAddCallIndex
    | DequeFilterEvenIndex
    | DequeMapAddCallIndex
    | DequeMapiAddIndex
    | DequeChunkByNondecreasing
    | DequeChunkByEvenBoundary
    | DequeReverseInPlace
    | DequeShrinkToFit
    | DequeAddSelf
    | DequeCopy
    | DequeRev
    | DequeToJson
    | DequeShuffleZero
    | DequeShuffleInPlaceZero
    | DequeShuffleLinear
    | DequeShuffleInPlaceLinear => []
  }
}

///|
fn deque_small_value(rng : @splitmix.RandomState) -> Int32 {
  rng.next_positive_int() % 13 - 6
}

///|
fn deque_small_array(rng : @splitmix.RandomState) -> Array[Int32] {
  let values : Array[Int32] = []
  let len = rng.next_positive_int() % 4
  for _ in 0..<len {
    values.push(deque_small_value(rng))
  }
  values
}

///|
fn deque_range_array(len : Int32) -> Array[Int32] {
  let values : Array[Int32] = []
  for index in 0..<len {
    values.push(index + 11)
  }
  values
}

///|
fn deque_string_range_array(len : Int32) -> Array[String] {
  let values : Array[String] = []
  for index in 0..<len {
    values.push("value-\{index + 11}")
  }
  values
}

///|
fn deque_string_array_drain(
  source : Array[String],
  start : Int32,
  len : Int32,
) -> (Array[String], Array[String]) {
  let drained : Array[String] = []
  let kept : Array[String] = []
  for index, value in source {
    if start <= index && index < start + len {
      drained.push(value)
    } else {
      kept.push(value)
    }
  }
  (drained, kept)
}

///|
fn deque_string_array_even_index(source : Array[String]) -> Array[String] {
  let kept : Array[String] = []
  for index, value in source {
    if index % 2 == 0 {
      kept.push(value)
    }
  }
  kept
}

///|
fn deque_string_array_map_call_index(source : Array[String]) -> Array[String] {
  let mapped : Array[String] = []
  for index, value in source {
    mapped.push("\{value}:\{index}")
  }
  mapped
}

///|
fn deque_string_array_retain_map_call_index(
  source : Array[String],
) -> Array[String] {
  let kept : Array[String] = []
  for index, value in source {
    if index % 2 == 0 {
      kept.push("\{value}:\{index}")
    }
  }
  kept
}

///|
fn deque_string_array_blit_to(
  source : Array[String],
  dst : Array[String],
  src_offset : Int32,
  dst_offset : Int32,
  len : Int32,
) -> Array[String] {
  let result = dst.copy()
  let required_len = dst_offset + len
  while result.length() < required_len {
    result.push("__fill__")
  }
  for offset in 0..<len {
    result[dst_offset + offset] = source[src_offset + offset]
  }
  result
}

///|
fn deque_string_array_flatten(nested : Array[Array[String]]) -> Array[String] {
  let flattened : Array[String] = []
  for values in nested {
    for value in values {
      flattened.push(value)
    }
  }
  flattened
}

///|
fn deque_string_join_model(
  values : Array[String],
  separator : String,
) -> String {
  let mut joined = ""
  for index, value in values {
    if index > 0 {
      joined = joined + separator
    }
    joined = joined + value
  }
  joined
}

///|
fn deque_random_generator(
  model : DequeModel,
  size : Int32,
  rng : @splitmix.RandomState,
) -> DequeCommand? {
  ignore(size)
  let len = model.values.length()
  let choices : Array[DequeCommand] = [
    DequeConstruct(deque_small_array(rng), rng.next_positive_int() % 10),
    DequeFromIter(deque_small_array(rng)),
    DequeFromJson(deque_small_array(rng)),
    DequeReset(deque_small_array(rng), rng.next_positive_int() % 10),
    DequeResetFromJson(deque_small_array(rng)),
    DequeResetWrapped(deque_small_array(rng)),
    DequeFront,
    DequeBack,
    DequePopFront,
    DequePopBack,
    DequeGet(rng.next_positive_int() % (len + 3)),
    DequeTruncate(rng.next_positive_int() % 21 - 3),
    DequeDrainToEnd(rng.next_positive_int() % (len + 1)),
    DequeRetainAtLeast(rng.next_positive_int() % 9 - 4),
    DequeRetainMapEven(rng.next_positive_int() % 5 - 2),
    DequeRetainEvenIndex,
    DequeRetainMapAddCallIndex,
    DequeExtractBelow(rng.next_positive_int() % 9 - 4),
    DequeFilterAtLeast(rng.next_positive_int() % 9 - 4),
    DequeFilterEvenIndex,
    DequeMapAdd(rng.next_positive_int() % 5 - 2),
    DequeMapAddCallIndex,
    DequeMapiAddIndex,
    DequeChunkByNondecreasing,
    DequeChunkByEvenBoundary,
    DequeFlatten([deque_small_array(rng), deque_small_array(rng)]),
    DequeFlattenWrapped([deque_small_array(rng), deque_small_array(rng)]),
    DequeFlattenSlack([deque_small_array(rng), deque_small_array(rng)]),
    DequeFlattenWrappedSlack([deque_small_array(rng), deque_small_array(rng)]),
    DequeReverseInPlace,
    DequeClear,
    DequeReserveCapacity(rng.next_positive_int() % 24),
    DequeShrinkToFit,
    DequeAdd(deque_small_array(rng)),
    DequeAddSelf,
    DequeAddWrapped(deque_small_array(rng)),
    DequeCopy,
    DequeRev,
    DequeToJson,
    DequeContains(deque_small_value(rng)),
    DequeSearch(deque_small_value(rng)),
    DequeEqual(deque_small_array(rng)),
    DequeCompare(deque_small_array(rng)),
    DequeNotEqual(deque_small_array(rng)),
    DequeLessThan(deque_small_array(rng)),
    DequeLessEqual(deque_small_array(rng)),
    DequeGreaterThan(deque_small_array(rng)),
    DequeGreaterEqual(deque_small_array(rng)),
    DequeShuffleZero,
    DequeShuffleInPlaceZero,
    DequeShuffleLinear,
    DequeShuffleInPlaceLinear,
  ]
  if deque_array_is_sorted(model.values) {
    choices.push(DequeBinarySearch(deque_small_value(rng)))
    choices.push(DequeBinarySearchBy(deque_small_value(rng)))
  }
  if len < 24 {
    choices.push(DequePushBack(deque_small_value(rng)))
    choices.push(DequePushFront(deque_small_value(rng)))
    choices.push(
      DequeInsert(rng.next_positive_int() % (len + 1), deque_small_value(rng)),
    )
    choices.push(DequeAppend(deque_small_array(rng)))
    choices.push(DequeAppendWrapped(deque_small_array(rng)))
    if len > 0 && len < 12 {
      choices.push(DequeAppendSelf)
    }
  }
  if len > 0 {
    choices.push(DequeUnsafePopFront)
    choices.push(DequeUnsafePopBack)
    choices.push(DequeAt(rng.next_positive_int() % len))
    choices.push(
      DequeSet(rng.next_positive_int() % len, deque_small_value(rng)),
    )
    choices.push(DequeRemove(rng.next_positive_int() % len))
    let start = rng.next_positive_int() % (len + 1)
    choices.push(DequeDrain(start, rng.next_positive_int() % (len - start + 1)))
    let blit_len = rng.next_positive_int() % (len + 1)
    let src_offset = rng.next_positive_int() % (len - blit_len + 1)
    let dst = deque_small_array(rng)
    let dst_offset = rng.next_positive_int() % (dst.length() + 1)
    choices.push(DequeBlitTo(dst, src_offset, dst_offset, blit_len))
    choices.push(DequeBlitToWrappedDst(dst, src_offset, dst_offset, blit_len))
    let self_blit_len = rng.next_positive_int() % (len + 1)
    let self_src_offset = rng.next_positive_int() % (len - self_blit_len + 1)
    let self_dst_offset = rng.next_positive_int() % (len + 1)
    choices.push(DequeBlitSelf(self_src_offset, self_dst_offset, self_blit_len))
    choices.push(DequeChunks(rng.next_positive_int() % 5 + 1))
  }
  Some(choices[rng.next_positive_int() % choices.length()])
}

///|
fn deque_storage_generator(
  model : DequeModel,
  size : Int32,
  rng : @splitmix.RandomState,
) -> DequeCommand? {
  ignore(size)
  let len = model.values.length()
  let choices : Array[DequeCommand] = [
    DequeReset(deque_small_array(rng), rng.next_positive_int() % 16),
    DequeResetFromJson(deque_small_array(rng)),
    DequeResetWrapped(deque_small_array(rng)),
    DequeFront,
    DequeBack,
    DequeToJson,
    DequeCopy,
    DequeRev,
    DequeReverseInPlace,
    DequeReserveCapacity(rng.next_positive_int() % 32),
    DequeShrinkToFit,
    DequeRetainAtLeast(rng.next_positive_int() % 9 - 4),
    DequeRetainMapEven(rng.next_positive_int() % 5 - 2),
    DequeRetainEvenIndex,
    DequeRetainMapAddCallIndex,
    DequeExtractBelow(rng.next_positive_int() % 9 - 4),
    DequeFilterAtLeast(rng.next_positive_int() % 9 - 4),
    DequeFilterEvenIndex,
    DequeMapAdd(rng.next_positive_int() % 5 - 2),
    DequeMapAddCallIndex,
    DequeMapiAddIndex,
    DequeChunkByNondecreasing,
    DequeChunkByEvenBoundary,
    DequeFlattenWrapped([deque_small_array(rng), deque_small_array(rng)]),
    DequeFlattenSlack([deque_small_array(rng), deque_small_array(rng)]),
    DequeFlattenWrappedSlack([deque_small_array(rng), deque_small_array(rng)]),
    DequeAddSelf,
    DequeAddWrapped(deque_small_array(rng)),
    DequeShuffleLinear,
    DequeShuffleInPlaceLinear,
  ]
  if len < 32 {
    choices.push(DequePushBack(deque_small_value(rng)))
    choices.push(DequePushFront(deque_small_value(rng)))
    choices.push(
      DequeInsert(rng.next_positive_int() % (len + 1), deque_small_value(rng)),
    )
    choices.push(DequeAppendWrapped(deque_small_array(rng)))
    if len > 0 && len < 16 {
      choices.push(DequeAppendSelf)
    }
  }
  if len > 0 {
    choices.push(DequeUnsafePopFront)
    choices.push(DequeUnsafePopBack)
    choices.push(DequePopFront)
    choices.push(DequePopBack)
    choices.push(DequeAt(rng.next_positive_int() % len))
    choices.push(
      DequeSet(rng.next_positive_int() % len, deque_small_value(rng)),
    )
    choices.push(DequeRemove(rng.next_positive_int() % len))
    let start = rng.next_positive_int() % (len + 1)
    choices.push(DequeDrain(start, rng.next_positive_int() % (len - start + 1)))
    choices.push(DequeDrainToEnd(rng.next_positive_int() % (len + 1)))
    let blit_len = rng.next_positive_int() % (len + 1)
    let src_offset = rng.next_positive_int() % (len - blit_len + 1)
    let dst = deque_small_array(rng)
    let dst_offset = rng.next_positive_int() % (dst.length() + 1)
    choices.push(DequeBlitToWrappedDst(dst, src_offset, dst_offset, blit_len))
    let self_blit_len = rng.next_positive_int() % (len + 1)
    let self_src_offset = rng.next_positive_int() % (len - self_blit_len + 1)
    let self_dst_offset = rng.next_positive_int() % (len + 1)
    choices.push(DequeBlitSelf(self_src_offset, self_dst_offset, self_blit_len))
    choices.push(DequeChunks(rng.next_positive_int() % 6 + 1))
  }
  if deque_array_is_sorted(model.values) {
    choices.push(DequeBinarySearch(deque_small_value(rng)))
    choices.push(DequeBinarySearchBy(deque_small_value(rng)))
  }
  Some(choices[rng.next_positive_int() % choices.length()])
}

///|
fn deque_drain_generator(
  model : DequeModel,
  size : Int32,
  rng : @splitmix.RandomState,
) -> DequeCommand? {
  ignore(size)
  let len = model.values.length()
  let choices : Array[DequeCommand] = []
  if len == 0 {
    choices.push(DequeResetWrapped(deque_small_array(rng)))
    choices.push(DequePushBack(deque_small_value(rng)))
    choices.push(DequePushFront(deque_small_value(rng)))
  } else if len < 18 {
    choices.push(DequePushBack(deque_small_value(rng)))
    choices.push(DequePushFront(deque_small_value(rng)))
    choices.push(DequePopFront)
    choices.push(DequePopBack)
    choices.push(DequeUnsafePopFront)
    choices.push(DequeUnsafePopBack)
    choices.push(DequeAppendWrapped(deque_small_array(rng)))
  } else {
    choices.push(DequePopFront)
    choices.push(DequePopBack)
    choices.push(DequeUnsafePopFront)
    choices.push(DequeUnsafePopBack)
    choices.push(DequeTruncate(rng.next_positive_int() % (len + 1)))
  }
  if len > 0 {
    let start = rng.next_positive_int() % (len + 1)
    let drain_len = rng.next_positive_int() % (len - start + 1)
    choices.push(DequeDrain(start, drain_len))
    choices.push(DequeDrainToEnd(start))
    choices.push(DequeDrain(0, rng.next_positive_int() % (len + 1)))
    choices.push(
      DequeDrain(len / 2, rng.next_positive_int() % (len - len / 2 + 1)),
    )
    choices.push(DequeDrain(len - 1, 1))
    choices.push(DequeClear)
    choices.push(DequeRetainAtLeast(rng.next_positive_int() % 9 - 4))
    choices.push(DequeRetainMapEven(rng.next_positive_int() % 5 - 2))
    choices.push(DequeRetainEvenIndex)
    choices.push(DequeRetainMapAddCallIndex)
    choices.push(DequeExtractBelow(rng.next_positive_int() % 9 - 4))
    choices.push(DequeReverseInPlace)
    choices.push(DequeShrinkToFit)
    choices.push(DequeReserveCapacity(rng.next_positive_int() % 40))
    choices.push(DequeCopy)
    choices.push(DequeRev)
    choices.push(DequeToJson)
    choices.push(DequeAddSelf)
    choices.push(DequeChunkByEvenBoundary)
  }
  if len > 1 {
    choices.push(DequeDrain(1, len - 1))
    choices.push(DequeDrain(0, len - 1))
    choices.push(DequeDrain(0, len))
  }
  Some(choices[rng.next_positive_int() % choices.length()])
}

///|
fn deque_base_spec(
  generator : (DequeModel, Int32, @splitmix.RandomState) -> DequeCommand?,
) -> @quickcheck_statemachine.StateMachine[
  DequeModel,
  DequeModel,
  DequeCommand,
  DequeCommand,
  DequeResponse,
  DequeResponse,
  Unit,
  DequeSystem,
] {
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=deque_empty_model,
    init_concrete_model=deque_empty_model,
    init_system=() => deque_empty_system(),
    generator~,
    mock=(model, command, gen_sym) => {
      (deque_expected_response(model, command), gen_sym)
    },
    transition_symbolic=(model, command, response) => {
      ignore(response)
      deque_transition(model, command)
    },
    transition_concrete=(model, command, response) => {
      deque_transition_from_response(model, command, response)
    },
    precondition=deque_precondition,
    postcondition=deque_postcondition,
    reify_command=deque_reify_command,
    run_command=(command, system) => run_deque_command(command, system),
    bind_response=deque_bind_response,
    shrinker=deque_shrinker,
    command_name=deque_command_name,
  )
}

///|
fn deque_random_spec() -> @quickcheck_statemachine.StateMachine[
  DequeModel,
  DequeModel,
  DequeCommand,
  DequeCommand,
  DequeResponse,
  DequeResponse,
  Unit,
  DequeSystem,
] {
  deque_base_spec(deque_random_generator)
}

///|
fn deque_storage_spec() -> @quickcheck_statemachine.StateMachine[
  DequeModel,
  DequeModel,
  DequeCommand,
  DequeCommand,
  DequeResponse,
  DequeResponse,
  Unit,
  DequeSystem,
] {
  deque_base_spec(deque_storage_generator)
}

///|
fn deque_drain_spec() -> @quickcheck_statemachine.StateMachine[
  DequeModel,
  DequeModel,
  DequeCommand,
  DequeCommand,
  DequeResponse,
  DequeResponse,
  Unit,
  DequeSystem,
] {
  deque_base_spec(deque_drain_generator)
}

///|
// Random state-machine property:
// This runs many generated command sequences against the standard-library deque
// and the Array model. The generator mixes empty/non-empty operations,
// wraparound-friendly push/pop patterns, indexed edits, filtering/extraction,
// capacity changes, and non-mutating views/copies. The property is that every
// response plus every snapshot observation remains equivalent to the model for
// all generated prefixes.
test "deque random operations preserve array semantics" {
  let summary = @quickcheck_statemachine.assert_check(
    deque_random_spec(),
    config=case_config(cases=100, max_commands=120, max_tries=50),
  )
  inspect(summary.cases_run, content="100")
  inspect(summary.commands_run, content="12000")
}

///|
test "deque storage-focused search preserves array semantics" {
  let summary = @quickcheck_statemachine.assert_check(
    deque_storage_spec(),
    config=case_config(cases=300, max_commands=160, max_tries=80),
  )
  inspect(summary.cases_run, content="300")
  inspect(summary.commands_run, content="48000")
}

///|
test "deque drain-focused search preserves array semantics" {
  let summary = @quickcheck_statemachine.assert_check(
    deque_drain_spec(),
    config=case_config(cases=500, max_commands=220, max_tries=80),
  )
  inspect(summary.cases_run, content="500")
  inspect(summary.commands_run, content="110000")
}

///|
test "deque exhaustive wrapped drain matches array model" {
  for len in 0..<9 {
    let values = deque_range_array(len)
    for slack in 0..<4 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        for start in 0..<(len + 1) {
          for drain_len in 0..<(len - start + 1) {
            let deque = deque_positioned_from_array(
              values, capacity, head_shift,
            )
            let (expected_drained, expected_kept) = deque_array_drain(
              values, start, drain_len,
            )
            let drained = deque.drain(start~, len=drain_len)
            assert_true(
              drained.to_array() == expected_drained,
              msg="drained mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start} drain_len=\{drain_len}",
            )
            assert_true(
              deque.to_array() == expected_kept,
              msg="kept mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start} drain_len=\{drain_len}",
            )
            assert_true(
              deque.capacity() == capacity,
              msg="capacity mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start} drain_len=\{drain_len}",
            )
          }
          let deque = deque_positioned_from_array(values, capacity, head_shift)
          let (expected_drained, expected_kept) = deque_array_drain_to_end(
            values, start,
          )
          let drained = deque.drain(start~)
          assert_true(
            drained.to_array() == expected_drained,
            msg="drain_to_end drained mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start}",
          )
          assert_true(
            deque.to_array() == expected_kept,
            msg="drain_to_end kept mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start}",
          )
          assert_true(
            deque.capacity() == capacity,
            msg="drain_to_end capacity mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start}",
          )
        }
      }
    }
  }
}

///|
test "deque exhaustive self blit matches array model" {
  for len in 0..<9 {
    let values = deque_range_array(len)
    for slack in 0..<5 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        for blit_len in 0..<(len + 1) {
          for src_offset in 0..<(len - blit_len + 1) {
            for dst_offset in 0..<(len + 1) {
              let deque = deque_positioned_from_array(
                values, capacity, head_shift,
              )
              deque.blit_to(deque, src_offset~, dst_offset~, len=blit_len)
              let expected = deque_array_blit_to(
                values, values, src_offset, dst_offset, blit_len,
              )
              assert_true(
                deque.to_array() == expected,
                msg="self blit mismatch len=\{len} capacity=\{capacity} head=\{head_shift} src=\{src_offset} dst=\{dst_offset} blit_len=\{blit_len}",
              )
            }
          }
        }
      }
    }
  }
}

///|
test "deque exhaustive insert and remove match array model" {
  for len in 0..<9 {
    let values = deque_range_array(len)
    for slack in 0..<4 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        for index in 0..<(len + 1) {
          let deque = deque_positioned_from_array(values, capacity, head_shift)
          let expected = values.copy()
          expected.insert(index, 42)
          deque.insert(index, 42)
          assert_true(
            deque.to_array() == expected,
            msg="insert mismatch len=\{len} capacity=\{capacity} head=\{head_shift} index=\{index}",
          )
        }
        for index in 0..<len {
          let deque = deque_positioned_from_array(values, capacity, head_shift)
          let expected = values.copy()
          let expected_removed = expected.remove(index)
          let removed = deque.remove(index)
          assert_true(
            removed == expected_removed,
            msg="remove result mismatch len=\{len} capacity=\{capacity} head=\{head_shift} index=\{index}",
          )
          assert_true(
            deque.to_array() == expected,
            msg="remove kept mismatch len=\{len} capacity=\{capacity} head=\{head_shift} index=\{index}",
          )
        }
      }
    }
  }
}

///|
test "deque exhaustive array view construction matches model" {
  for source_len in 0..<10 {
    let source = deque_range_array(source_len)
    for start in 0..<(source_len + 1) {
      for end in start..<(source_len + 1) {
        let expected : Array[Int32] = []
        for index in start..<end {
          expected.push(source[index])
        }
        for slack in 0..<4 {
          let capacity = expected.length() + slack
          let deque = @deque.Deque(source[start:end], capacity~)
          assert_true(
            deque.to_array() == expected,
            msg="view construction mismatch source_len=\{source_len} start=\{start} end=\{end} capacity=\{capacity}",
          )
          assert_true(
            deque.capacity() == capacity,
            msg="view construction capacity mismatch source_len=\{source_len} start=\{start} end=\{end} capacity=\{capacity}",
          )
        }
      }
    }
  }
}

///|
test "deque exhaustive higher order wrapped operations match array model" {
  for len in 0..<9 {
    let values = deque_range_array(len)
    for slack in 0..<4 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        for threshold in 9..<18 {
          let retained = deque_positioned_from_array(
            values, capacity, head_shift,
          )
          retained.retain(value => value >= threshold)
          assert_true(
            retained.to_array() ==
            deque_array_retain_at_least(values, threshold),
            msg="retain mismatch len=\{len} capacity=\{capacity} head=\{head_shift} threshold=\{threshold}",
          )

          let extracted_source = deque_positioned_from_array(
            values, capacity, head_shift,
          )
          let extracted = extracted_source.extract_if(value => value < threshold)
          let (expected_extracted, expected_kept) = deque_array_extract_below(
            values, threshold,
          )
          assert_true(
            extracted.to_array() == expected_extracted,
            msg="extract result mismatch len=\{len} capacity=\{capacity} head=\{head_shift} threshold=\{threshold}",
          )
          assert_true(
            extracted_source.to_array() == expected_kept,
            msg="extract kept mismatch len=\{len} capacity=\{capacity} head=\{head_shift} threshold=\{threshold}",
          )

          let filter_source = deque_positioned_from_array(
            values, capacity, head_shift,
          )
          let filtered = filter_source.filter(value => value >= threshold)
          assert_true(
            filtered.to_array() ==
            deque_array_filter_at_least(values, threshold),
            msg="filter result mismatch len=\{len} capacity=\{capacity} head=\{head_shift} threshold=\{threshold}",
          )
          assert_true(
            filter_source.to_array() == values,
            msg="filter mutated source len=\{len} capacity=\{capacity} head=\{head_shift} threshold=\{threshold}",
          )
        }
        for delta_index in 0..<5 {
          let delta = delta_index - 2
          let retained_map = deque_positioned_from_array(
            values, capacity, head_shift,
          )
          retained_map.retain_map(value => {
            deque_retain_map_even_value(value, delta)
          })
          assert_true(
            retained_map.to_array() ==
            deque_array_retain_map_even(values, delta),
            msg="retain_map mismatch len=\{len} capacity=\{capacity} head=\{head_shift} delta=\{delta}",
          )

          let map_source = deque_positioned_from_array(
            values, capacity, head_shift,
          )
          let mapped = map_source.map(value => value + delta)
          assert_true(
            mapped.to_array() == deque_array_map_add(values, delta),
            msg="map result mismatch len=\{len} capacity=\{capacity} head=\{head_shift} delta=\{delta}",
          )
          assert_true(
            map_source.to_array() == values,
            msg="map mutated source len=\{len} capacity=\{capacity} head=\{head_shift} delta=\{delta}",
          )
        }

        let retain_indexed = deque_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut retain_index = 0
        retain_indexed.retain(_value => {
          let keep = retain_index % 2 == 0
          retain_index += 1
          keep
        })
        assert_true(
          retain_indexed.to_array() == deque_array_even_index(values),
          msg="retain indexed mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let retain_map_indexed = deque_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut retain_map_index = 0
        retain_map_indexed.retain_map(value => {
          let current = retain_map_index
          retain_map_index += 1
          if current % 2 == 0 {
            Some(value + current)
          } else {
            None
          }
        })
        assert_true(
          retain_map_indexed.to_array() ==
          deque_array_retain_map_add_call_index(values),
          msg="retain_map indexed mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let filter_indexed_source = deque_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut filter_index = 0
        let filter_indexed = filter_indexed_source.filter(_value => {
          let keep = filter_index % 2 == 0
          filter_index += 1
          keep
        })
        assert_true(
          filter_indexed.to_array() == deque_array_even_index(values),
          msg="filter indexed result mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
        assert_true(
          filter_indexed_source.to_array() == values,
          msg="filter indexed mutated source len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let map_indexed_source = deque_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut map_index = 0
        let map_indexed = map_indexed_source.map(value => {
          let current = map_index
          map_index += 1
          value + current
        })
        assert_true(
          map_indexed.to_array() == deque_array_map_add_call_index(values),
          msg="map indexed result mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
        assert_true(
          map_indexed_source.to_array() == values,
          msg="map indexed mutated source len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
      }
    }
  }
}

///|
test "deque string wrapped operations match array model" {
  for len in 0..<8 {
    let values = deque_string_range_array(len)
    for slack in 0..<4 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        for start in 0..<(len + 1) {
          for drain_len in 0..<(len - start + 1) {
            let deque = deque_string_positioned_from_array(
              values, capacity, head_shift,
            )
            let drained = deque.drain(start~, len=drain_len)
            let (expected_drained, expected_kept) = deque_string_array_drain(
              values, start, drain_len,
            )
            assert_true(
              drained.to_array() == expected_drained,
              msg="string drain result mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start} drain_len=\{drain_len}",
            )
            assert_true(
              deque.to_array() == expected_kept,
              msg="string drain kept mismatch len=\{len} capacity=\{capacity} head=\{head_shift} start=\{start} drain_len=\{drain_len}",
            )
          }
        }

        for blit_len in 0..<(len + 1) {
          for src_offset in 0..<(len - blit_len + 1) {
            for dst_offset in 0..<(len + 1) {
              let deque = deque_string_positioned_from_array(
                values, capacity, head_shift,
              )
              deque.blit_to(deque, src_offset~, dst_offset~, len=blit_len)
              assert_true(
                deque.to_array() ==
                deque_string_array_blit_to(
                  values, values, src_offset, dst_offset, blit_len,
                ),
                msg="string self blit mismatch len=\{len} capacity=\{capacity} head=\{head_shift} src=\{src_offset} dst=\{dst_offset} blit_len=\{blit_len}",
              )
            }
          }
        }

        let retain_indexed = deque_string_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut retain_index = 0
        retain_indexed.retain(_value => {
          let keep = retain_index % 2 == 0
          retain_index += 1
          keep
        })
        assert_true(
          retain_indexed.to_array() == deque_string_array_even_index(values),
          msg="string retain indexed mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let retain_map_indexed = deque_string_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut retain_map_index = 0
        retain_map_indexed.retain_map(value => {
          let current = retain_map_index
          retain_map_index += 1
          if current % 2 == 0 {
            Some("\{value}:\{current}")
          } else {
            None
          }
        })
        assert_true(
          retain_map_indexed.to_array() ==
          deque_string_array_retain_map_call_index(values),
          msg="string retain_map indexed mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let filter_source = deque_string_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut filter_index = 0
        let filtered = filter_source.filter(_value => {
          let keep = filter_index % 2 == 0
          filter_index += 1
          keep
        })
        assert_true(
          filtered.to_array() == deque_string_array_even_index(values),
          msg="string filter indexed mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
        assert_true(
          filter_source.to_array() == values,
          msg="string filter mutated source len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let map_source = deque_string_positioned_from_array(
          values, capacity, head_shift,
        )
        let mut map_index = 0
        let mapped = map_source.map(value => {
          let current = map_index
          map_index += 1
          "\{value}:\{current}"
        })
        assert_true(
          mapped.to_array() == deque_string_array_map_call_index(values),
          msg="string map indexed mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
        assert_true(
          map_source.to_array() == values,
          msg="string map mutated source len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
      }
    }
  }
}

///|
test "deque string wrapped flatten matches array model" {
  for first_len in 0..<5 {
    for second_len in 0..<5 {
      for third_len in 0..<5 {
        let nested : Array[Array[String]] = [
          deque_string_range_array(first_len),
          deque_string_range_array(second_len),
          deque_string_range_array(third_len),
        ]
        let deques : Array[@deque.Deque[String]] = []
        for index, values in nested {
          deques.push(
            deque_string_positioned_from_array(
              values,
              values.length() + 3,
              index + 1,
            ),
          )
        }
        let outer = @deque.Deque([], capacity=deques.length() + 3)
        outer.push_back(deque_string_positioned_from_array([], 1, 0))
        ignore(outer.pop_front())
        for deque in deques {
          outer.push_back(deque)
        }
        let flattened = outer.flatten()
        assert_true(
          flattened.to_array() == deque_string_array_flatten(nested),
          msg="string flatten mismatch first=\{first_len} second=\{second_len} third=\{third_len}",
        )
      }
    }
  }
}

///|
test "deque wrapped hash and join match logical model" {
  for len in 0..<9 {
    let int_values = deque_range_array(len)
    let string_values = deque_string_range_array(len)
    for slack in 0..<4 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        let int_deque = deque_positioned_from_array(
          int_values, capacity, head_shift,
        )
        assert_true(
          int_deque.hash() == @deque.from_array(int_values).hash(),
          msg="int hash mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )

        let string_deque = deque_string_positioned_from_array(
          string_values, capacity, head_shift,
        )
        assert_true(
          string_deque.hash() == @deque.from_array(string_values).hash(),
          msg="string hash mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
        for separator in ["", ",", "::"] {
          assert_true(
            string_deque.join(separator) ==
            deque_string_join_model(string_values, separator),
            msg="join mismatch len=\{len} capacity=\{capacity} head=\{head_shift} separator=\{separator}",
          )
        }
      }
    }
  }
}

///|
test "deque wrapped as_views split matches storage model" {
  for len in 0..<10 {
    let values = deque_range_array(len)
    for slack in 0..<5 {
      let capacity = len + slack
      let head_limit = if capacity == 0 { 1 } else { capacity }
      for head_shift in 0..<head_limit {
        let deque = deque_positioned_from_array(values, capacity, head_shift)
        let (front, back) = deque.as_views()
        let expected_front : Array[Int32] = []
        let expected_back : Array[Int32] = []
        let front_len = if len == 0 {
          0
        } else {
          let head = head_shift % capacity
          deque_min(len, capacity - head)
        }
        for index in 0..<front_len {
          expected_front.push(values[index])
        }
        for index in front_len..<len {
          expected_back.push(values[index])
        }
        assert_true(
          front.iter().to_array() == expected_front,
          msg="as_views front mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
        assert_true(
          back.iter().to_array() == expected_back,
          msg="as_views back mismatch len=\{len} capacity=\{capacity} head=\{head_shift}",
        )
      }
    }
  }
}

///|
test "deque exhaustive wrapped blit_to matches array model" {
  for src_len in 0..<8 {
    let src_values = deque_range_array(src_len)
    for dst_len in 0..<8 {
      let dst_values = deque_range_array(dst_len)
      for src_slack in 0..<3 {
        let src_capacity = src_len + src_slack
        let src_head_limit = if src_capacity == 0 { 1 } else { src_capacity }
        for src_head in 0..<src_head_limit {
          for dst_slack in 0..<3 {
            let dst_capacity = dst_len + dst_slack
            let dst_head_limit = if dst_capacity == 0 {
              1
            } else {
              dst_capacity
            }
            for dst_head in 0..<dst_head_limit {
              for blit_len in 0..<(src_len + 1) {
                for src_offset in 0..<(src_len - blit_len + 1) {
                  for dst_offset in 0..<(dst_len + 1) {
                    let src = deque_positioned_from_array(
                      src_values, src_capacity, src_head,
                    )
                    let dst = deque_positioned_from_array(
                      dst_values, dst_capacity, dst_head,
                    )
                    src.blit_to(dst, src_offset~, dst_offset~, len=blit_len)
                    assert_true(
                      src.to_array() == src_values,
                      msg="blit_to mutated source src_len=\{src_len} dst_len=\{dst_len} src_capacity=\{src_capacity} dst_capacity=\{dst_capacity} src_head=\{src_head} dst_head=\{dst_head} src_offset=\{src_offset} dst_offset=\{dst_offset} blit_len=\{blit_len}",
                    )
                    assert_true(
                      dst.to_array() ==
                      deque_array_blit_to(
                        src_values, dst_values, src_offset, dst_offset, blit_len,
                      ),
                      msg="blit_to dst mismatch src_len=\{src_len} dst_len=\{dst_len} src_capacity=\{src_capacity} dst_capacity=\{dst_capacity} src_head=\{src_head} dst_head=\{dst_head} src_offset=\{src_offset} dst_offset=\{dst_offset} blit_len=\{blit_len}",
                    )
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

///|
fn deque_script(
  commands : Array[DequeCommand],
) -> @quickcheck_statemachine.Commands[DequeCommand, DequeResponse] {
  let scripted : Array[
    @quickcheck_statemachine.Command[DequeCommand, DequeResponse],
  ] = []
  for index = 0, model = deque_empty_model(); index < commands.length(); {
    let command = commands[index]
    scripted.push({
      command,
      response: deque_expected_response(model, command),
      vars: [],
    })
    continue index + 1, deque_transition(model, command)
  }
  { commands: scripted, }
}

///|
test "deque scripted operations cover derived and query APIs" {
  let commands : Array[DequeCommand] = [
    DequeConstruct([2, -4, 3], 7),
    DequeFromIter([1, 2, 3]),
    DequePushBack(1),
    DequePushBack(3),
    DequePushFront(0),
    DequeBinarySearch(2),
    DequeContains(1),
    DequeSearch(3),
    DequeFilterAtLeast(1),
    DequeMapAdd(2),
    DequeMapiAddIndex,
    DequeChunks(2),
    DequeBlitTo([9], 0, 1, 2),
    DequeAdd([4, 5]),
    DequeCopy,
    DequeRev,
    DequeDrain(1, 1),
    DequeExtractBelow(2),
  ]
  let summary = @quickcheck_statemachine.assert_replay(
    deque_random_spec(),
    deque_script(commands),
    config=case_config(max_commands=commands.length()),
  )
  inspect(summary.commands_run, content="18")
}

///|
test "deque scripted operations cover optional and higher order APIs" {
  let commands : Array[DequeCommand] = [
    DequePushBack(1),
    DequePushBack(3),
    DequePushBack(2),
    DequePushBack(4),
    DequeBinarySearchBy(3),
    DequeChunkByNondecreasing,
    DequeFlatten([[1, 2], [], [3]]),
    DequeEqual([1, 3, 2, 4]),
    DequeCompare([1, 3, 2]),
    DequeShuffleZero,
    DequeShuffleInPlaceZero,
    DequeDrainToEnd(2),
  ]
  let summary = @quickcheck_statemachine.assert_replay(
    deque_random_spec(),
    deque_script(commands),
    config=case_config(max_commands=commands.length()),
  )
  inspect(summary.commands_run, content="12")
}

///|
test "deque scripted operations cover equality and ordering operators" {
  let commands : Array[DequeCommand] = [
    DequePushBack(2),
    DequeNotEqual([2, 0]),
    DequeLessThan([2, 0]),
    DequeLessEqual([2]),
    DequeGreaterThan([1]),
    DequeGreaterEqual([3]),
  ]
  let summary = @quickcheck_statemachine.assert_replay(
    deque_random_spec(),
    deque_script(commands),
    config=case_config(max_commands=commands.length()),
  )
  inspect(summary.commands_run, content="6")
}

///|
test "deque model accepts negative truncate as no-op" {
  assert_true(
    deque_precondition(deque_model([1, 2, 3], capacity=8), DequeTruncate(-1)).eval(),
  )
}

///|
test "deque model rejects clear response that shrinks capacity" {
  let response = deque_model_response(DequeDone, deque_model([], capacity=0))
  assert_false(
    deque_postcondition(
      deque_model([1, 2, 3], capacity=8),
      DequeClear,
      response,
    ).eval(),
  )
}

///|
test "deque model rejects pop response that grows capacity" {
  let response = deque_model_response(
    DequeOptional(Some(3)),
    deque_model([1, 2], capacity=16),
  )
  assert_false(
    deque_postcondition(
      deque_model([1, 2, 3], capacity=8),
      DequePopBack,
      response,
    ).eval(),
  )
}
