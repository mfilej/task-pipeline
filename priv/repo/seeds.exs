# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

TaskPipeline.Seeds.create_tasks()
TaskPipeline.Seeds.create_runs()
