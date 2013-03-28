require "rubygems"
module ChordUtility
  # ()
  def rangeOO(key, lo, hi)
      return  ((key > lo and key < hi) ||
      (key > lo and lo >= hi) ||
      (key < hi and hi <= lo))
  end

  # (]
  def rangeOC(key, lo, hi)
    return  ((key > lo and key <= hi) ||
    (key > lo and lo >= hi) ||
    (key <= hi and hi <= lo))
  end
  
  # [)
  def rangeCO(key, lo, hi)
    return  ((key >= lo and key < hi) ||
    (key >= lo and lo >= hi) ||
    (key < hi and hi <= lo))
  end

  # []
  def rangeCC(key, lo, hi)
    return  ((key >= lo and key <= hi) ||
    (key >= lo and lo >= hi) ||
    (key <= hi and hi <= lo))
  end
end
