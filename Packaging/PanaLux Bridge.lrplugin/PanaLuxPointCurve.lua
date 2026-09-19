-- PanaLux Bridge, GPL-3.0-or-later. Pure SDR point-curve transform.
-- Retains the existing MIDI2LR endpoint shaping; rejects unsupported data.
local function adjust(points, blacks, moveup)
  if type(points) ~= 'table' or #points < 4 or #points % 2 ~= 0 then return nil end
  local previous = -1
  for i = 1, #points do
    local v = points[i]
    if type(v) ~= 'number' or v ~= v or v < 0 or v > 255 then return nil end
    if i % 2 == 1 then
      if v <= previous then return nil end
      previous = v
    end
  end
    local maxamount = 5
    local  factor  = 0
    local newpoints = {}
    local xval = 0
    local testamount = 0
    -- Find the left and right most points
    local xmin, ymin, xmax, ymax, xmindid, xmaxdid = nil, nil, nil, nil, false, false
    for idx,val in ipairs(points) do
      if math.floor(idx/2) ~= idx/2 then -- odd number, i.e. x
        if val < (xmin or 256) then xmin = val; xmindid = true end
        if val > (xmax or 0) then xmax = val; xmaxdid = true end
      elseif xmindid then
        ymin = val
        xmindid = false
      elseif xmaxdid then
        ymax = val
        xmaxdid = false
      end
    end
    -- There are two scales (explanation for blacks):
    -- xscale: diminishes the point movement the further right the point is, where the left most point has full effect (1 => maxamount), the right most point has 0 (does not move at all)
    -- yscale: is the percentage how much maxamount is in relation to the y-value of the leftmost point; this is for awkward curves where the leftmost point is not the lowest one,
    -- in such cases the points lower than the leftmost have to be affected more to keep the shape of the curve intact, as those values are more 'extreme', they are affected more
    if xmax <= xmin or (blacks and ymin >= 255) or (not blacks and ymax <= 0) then return nil end
    local yscale = 0
    local xscale = 0
    if blacks then
      if not moveup and ymin < maxamount then maxamount = ymin end
      yscale = maxamount / (255 - ymin)
    else
      if moveup and (255 - ymax) < maxamount then maxamount = (255 - ymax) end
      yscale = maxamount / ymax
    end
    xscale = 1 / (xmax - xmin)
    -- Now all points are moved. 'factor' is the diminishing effect of xscale depending on the actual x-value of the point
    for idx,val in ipairs(points) do
      if math.floor(idx/2) ~= idx/2 then -- odd number, i.e. x
        if blacks then
          factor  = 1 - (xscale * (val - xmin))^2.5
        else
          factor  = 1 - (xscale * (xmax - val))^2.5
        end
        xval = val
      else -- even number, i.e. y
        newpoints[#newpoints+1] = xval
        if not moveup then  factor  =  factor  * -1 end
        if blacks then
          testamount = val + yscale * (255 - val) * factor
        else
          testamount = val + yscale * val * factor
        end
        if testamount < 0 then testamount = 0 end
        if testamount > 255 then testamount = 255 end
        newpoints[#newpoints+1] = testamount
      end
    end
  return newpoints
end
return {adjust = adjust}
