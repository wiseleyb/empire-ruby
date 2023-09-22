# game.c -- Routines to initialize, save, and restore a game.

# Testing:
# IRB
#   require_relative 'game'


require 'securerandom'
require 'json'

LIST_SIZE = 10
MAP_CITY = 'C'
MAP_LAND = '+'
MAP_SEA = '.'
MAP_SIZE = 3 * 3 # ?
MAP_WIDTH = 1 # ?
MAX_HEIGHT = 3 # ?
NOPIECE = '_' # ?
NOFUNC = 1 # ?
NUM_CITY = 2
NUM_OBJECTS = 3
SMOOTH = 3
UNOWNED = '0' # ?

# TODO
# convert to dynamic
DIR_OFFSET = [
  -MAP_WIDTH,   # north
  -MAP_WIDTH+1, # northeast
  1,            # east
  MAP_WIDTH+1,  #  southeast
  MAP_WIDTH,    # south
  MAP_WIDTH-1,  # southwest
  -1,           # west
  -MAP_WIDTH-1  # northwest
]


class Game
  attr_accessor :automove,
    :resigned,
    :debug,
    :print_debug,
    :print_vmap,
    :trace_pmap,
    :save_movie,
    :win,
    :date,
    :user_score,
    :comp_score

  attr_reader :real_map,
    :comp_map,
    :user_map,
    :city,
    :object,
    :user_obj,
    :comp_obj,
    :free_list

  def initialize
    @real_map = Array.new(MAP_SIZE) { Cell.new }
    @comp_map = Array.new(MAP_SIZE) { Cell.new }
    @user_map = Array.new(MAP_SIZE) { Cell.new }
    @city = Array.new(NUM_CITY) { City.new }
    @object = Array.new(LIST_SIZE) { PieceInfo.new }
    @user_obj = Array.new(NUM_OBJECTS)
    @comp_obj = Array.new(NUM_OBJECTS)
    @free_list = nil
    @automove = false
    @resigned = false
    @debug = false
    @print_debug = false
    @print_vmap = false
    @trace_pmap = false
    @save_movie = false
    @win = :no_win
    @date = 0
    @user_score = 0
    @comp_score = 0
  end

  def init_game
    make_map
    place_cities
    select_cities
  end

  def save_game
    save_data = {
      "real_map" => @real_map,
      "comp_map" => @comp_map,
      "user_map" => @user_map,
      "city" => @city,
      "object" => @object,
      "user_obj" => @user_obj,
      "comp_obj" => @comp_obj,
      "free_list" => @free_list,
      "date" => @date,
      "automove" => @automove,
      "resigned" => @resigned,
      "debug" => @debug,
      "win" => @win,
      "save_movie" => @save_movie,
      "user_score" => @user_score,
      "comp_score" => @comp_score
    }

    File.open("emp_save.dat", "w") do |file|
      file.write(JSON.dump(save_data))
    end

    puts "Game saved."
  end

  def restore_game
    save_data = JSON.parse(File.read("emp_save.dat"))

    @real_map = save_data["real_map"]
    @comp_map = save_data["comp_map"]
    @user_map = save_data["user_map"]
    @city = save_data["city"]
    @object = save_data["object"]
    @user_obj = save_data["user_obj"]
    @comp_obj = save_data["comp_obj"]
    @free_list = save_data["free_list"]
    @date = save_data["date"]
    @automove = save_data["automove"]
    @resigned = save_data["resigned"]
    @debug = save_data["debug"]
    @win = save_data["win"]
    @save_movie = save_data["save_movie"]
    @user_score = save_data["user_score"]
    @comp_score = save_data["comp_score"]

    puts "Game restored from save file."
  end

#  private

  def make_map
    height = Array.new(2) { Array.new(MAP_SIZE + 1) }
    height_count = Array.new(MAX_HEIGHT + 1, 0)

    for i in 0...MAP_SIZE
      height[0][i] = rand(MAX_HEIGHT)
    end

    from = 0
    to = 1

    for i in 0...SMOOTH
      for j in 0...MAP_SIZE
        sum = height[from][j]
        for k in 0...8
          loc = j + DIR_OFFSET[k]
          if loc < 0 || loc >= MAP_SIZE
            loc = j
          end
          sum += height[from][loc]
        end
        height[to][j] = sum / 9
      end
      k = to
      to = from
      from = k
    end

    for i in 0..MAX_HEIGHT
      height_count[i] = 0
    end

    for i in 0..MAP_SIZE
      height_count[height[from][i]] ||= 0
      height_count[height[from][i]] += 1
    end

    loc = MAX_HEIGHT
    sum = 0

    for i in 0..MAX_HEIGHT
      sum += height_count[i]
      if sum * 100 / MAP_SIZE > game.WATER_RATIO && sum >= NUM_CITY
        loc = i
        break
      end
    end

    for i in 0...MAP_SIZE
      if height[from][i] > loc
        @real_map[i].contents = MAP_LAND
      else
        @real_map[i].contents = MAP_SEA
      end
      @real_map[i].objp = nil
      @real_map[i].cityp = nil
      j = loc_col(i)
      k = loc_row(i)
      @real_map[i].on_board = !(j == 0 || j == MAP_WIDTH - 1 || k == 0 || k == MAP_HEIGHT - 1)
    end
  end

  def place_cities
    land = Array.new(MAP_SIZE)
    num_land = 0
    placed = 0

    while placed < NUM_CITY
      num_land = regen_land(placed)

      i = rand(num_land - 1)
      loc = land[i]

      @city[placed].loc = loc
      @city[placed].owner = UNOWNED
      @city[placed].work = 0
      @city[placed].prod = NOPIECE

      for i in 0...NUM_OBJECTS
        @city[placed].func[i] = NOFUNC
      end

      @real_map[loc].contents = MAP_CITY
      @real_map[loc].cityp = @city[placed]

      placed += 1

      num_land = remove_land(loc, num_land)
    end
  end

  def regen_land(placed)
    num_land = 0

    for i in 0...MAP_SIZE
      if @real_map[i].on_board && @real_map[i].contents == MAP_LAND
        land[num_land] = i
        num_land += 1
      end
    end

    if placed > 0
      @MIN_CITY_DIST -= 1
      raise "MIN_CITY_DIST must be greater than or equal to 0" if @MIN_CITY_DIST < 0
    end

    for i in 0...placed
      num_land = remove_land(@city[i].loc, num_land)
    end

    num_land
  end

  def remove_land(loc, num_land)
    new_land = 0

    for i in 0...num_land
      if dist(loc, land[i]) >= @MIN_CITY_DIST
        land[new_land] = land[i]
        new_land += 1
      end
    end

    new_land
  end

  def select_cities
    find_cont
    return false if ncont == 0
    make_pair

    puts "Choose a difficulty level where 0 is easy and #{ncont * ncont - 1} is hard: "
    pair = gets.chomp.to_i

    comp_cont = pair_tab[pair].comp_cont
    user_cont = pair_tab[pair].user_cont

    compi = rand(cont_tab[comp_cont].ncity)
    compp = cont_tab[comp_cont].cityp[compi]

    begin
      useri = rand(cont_tab[user_cont].ncity)
      userp = cont_tab[user_cont].cityp[useri]
    end while userp == compp

    puts "Your city is at #{loc_disp(userp.loc)}"
    set_prod(userp)

    true
  end

  def find_cont
    marked = Array.new(MAP_SIZE, 0)
    ncont = 0
    mapi = 0

    while ncont < MAX_CONT
      return if !find_next(mapi)
    end
  end

  def find_next(mapi)
    i = 0
    val = 0

    loop do
      return false if mapi >= MAP_SIZE
      if !@real_map[mapi].on_board || marked[mapi] || @real_map[mapi].contents == MAP_SEA
        mapi += 1
      elsif good_cont(mapi)
        rank_tab[ncont] = ncont
        val = cont_tab[ncont].value

        i = ncont
        while i > 0
          if val > cont_tab[rank_tab[i - 1]].value
            rank_tab[i] = rank_tab[i - 1]
            rank_tab[i - 1] = ncont
          else
            break
          end
          i -= 1
        end

        ncont += 1
        return true
      end
    end
  end

  def good_cont(mapi)
    val = 0
    ncity = 0
    nland = 0
    nshore = 0

    mark_cont(mapi)

    return false if nshore < 1 || ncity < 2

    if ncity == nshore
      val = (nshore - 2) * 3
    else
      val = (nshore - 1) * 3 + (ncity - nshore - 1) * 2
    end

    val *= 1000
    val += nland

    cont_tab[ncont].value = val
    cont_tab[ncont].ncity = ncity

    true
  end

  def mark_cont(mapi)
    return if marked[mapi] || @real_map[mapi].contents == MAP_SEA || !@real_map[mapi].on_board

    marked[mapi] = 1
    nland += 1

    if @real_map[mapi].contents == MAP_CITY
      cont_tab[ncont].cityp[ncity] = @real_map[mapi].cityp
      ncity += 1
      nshore += 1 if rmap_shore(mapi)
    end

    for i in 0...8
      mark_cont(mapi + DIR_OFFSET[i])
    end
  end

  def make_pair
    npair = 0

    for i in 0...ncont
      for j in 0...ncont
        val = cont_tab[i].value - cont_tab[j].value
        pair_tab[npair].value = val
        pair_tab[npair].user_cont = i
        pair_tab[npair].comp_cont = j

        k = npair
        while k > 0
          if val > pair_tab[k - 1].value
            pair_tab[k] = pair_tab[k - 1]
            pair_tab[k - 1].user_cont = i
            pair_tab[k - 1].comp_cont = j
          else
            break
          end
          k -= 1
        end

        npair += 1
      end
    end
  end
end

class Cell
  attr_accessor :contents, :objp, :cityp, :on_board

  def initialize
    @contents = ' '
    @objp = nil
    @cityp = nil
    @on_board = false
  end
end

class City
  attr_accessor :loc, :owner, :work, :prod, :func

  def initialize
    @loc = 0
    @owner = UNOWNED
    @work = 0
    @prod = NOPIECE
    @func = Array.new(NUM_OBJECTS, NOFUNC)
  end
end

class PieceInfo
  attr_accessor :hits, :owner, :loc_link, :cargo_link, :piece_link, :ship, :cargo, :count, :type, :loc

  def initialize
    @hits = 0
    @owner = UNOWNED
    @loc_link = Link.new
    @cargo_link = Link.new
    @piece_link = Link.new
    @ship = nil
    @cargo = nil
    @count = 0
    @type = 0
    @loc = 0
  end
end

class Link
  attr_accessor :next, :prev

  def initialize
    @next = nil
    @prev = nil
  end
end

game = Game.new
game.init_game
game.save_game
game.restore_game

