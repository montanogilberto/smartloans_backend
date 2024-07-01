from fastapi import APIRouter
from modules.projects import projects_sp, all_projects_sp, one_project_sp

router = APIRouter()

# Read projects docstring from the file
with open("./docs_description/projects.txt", "r") as file:
    projects_docstring = file.read()
@router.post("/projects", summary="projects CRUD", description=projects_docstring)
def projects(json: dict):
    return projects_sp(json)


# Read all projects docstring from the file
with open("./docs_description/projects_all.txt", "r") as file:
    projects_all_docstring = file.read()
@router.get("/all_projects", summary="all projects", description=projects_all_docstring)
def all_projects():
    return all_projects_sp()


# Read one project docstring from the file
with open("./docs_description/projects_one.txt", "r") as file:
    project_one_docstring = file.read()
@router.post("/one_project", summary="one project", description=project_one_docstring)
def one_project(json: dict):
    return one_project_sp(json)
