
/// @func Buffer(_count, _layout);
/// @desc
/// @param  {Real} _count
/// @param  {Any} _layout
function Buffer(_count=1, _layout=[buffer_f32]) constructor
{
  // Declare variables.
  self.count = 1;
  self.layout = [];
  self.stride = 1;
  self.bytes = 1;
  self.buffer = undefined;

  // Define variables.
  self.count = _count;
  self.layout = is_array(_layout) ? _layout : [_layout];
  array_foreach(self.layout, function(_dtype, i)
  {
    self.stride += buffer_sizeof(_dtype);
  });
  self.bytes = self.stride * self.count;
  self.buffer = buffer_create(self.bytes, buffer_fixed, 1);
  
  // Delete buffer.
  static Free = function()
  {
    buffer_delete(self.buffer);
    self.count = undefined;
    self.layout = undefined;
    self.stride = undefined;
    self.bytes = undefined;
    self.buffer = undefined;
    return self;
  };
}