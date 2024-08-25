import random
import pygame
import numpy as np
import sys
pygame.font.init()

from player import Player
from card import Card
from deck import Deck
from pokerwindow import PokerWindow
from global_variables import *

pw = PokerWindow()
pw.add_player("Dina")
pw.play()