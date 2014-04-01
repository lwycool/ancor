# Author: Ian Unruh, Alexandru G. Bardas
# Copyright (C) 2013-2014 Argus Cybersecurity Lab, Kansas State University
#
# This file is part of ANCOR.
#
# ANCOR is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ANCOR is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with ANCOR.  If not, see <http://www.gnu.org/licenses/>.
module V1
  class HomeController < ApplicationController
    def index
      render json: { version: '0.0.1' }
    end

    def options
      headers['Access-Control-Allow-Origin'] = '*'
      headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'

      head :ok
    end
  end
end
