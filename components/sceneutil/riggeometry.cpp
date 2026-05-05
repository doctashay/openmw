#include "riggeometry.hpp"

#include <cstring>
#include <unordered_map>

#include <osg/MatrixTransform>

#include <osgUtil/CullVisitor>

#include <components/debug/debuglog.hpp>
#include <components/misc/strings/algorithm.hpp>
#include <components/resource/scenemanager.hpp>

#include "skeleton.hpp"
#include "util.hpp"

#if defined(OPENMW_HAVE_ALTIVEC)
#include <altivec.h>
#ifdef bool
#undef bool
#endif
#ifdef vector
#undef vector
#endif
#ifdef pixel
#undef pixel
#endif
#endif

namespace
{
#if defined(OPENMW_HAVE_ALTIVEC)
    using FloatVector = __vector float;

    inline FloatVector loadFloatVector(const float* data)
    {
        FloatVector result;
        std::memcpy(&result, data, sizeof(result));
        return result;
    }

    inline void storeFloatVector(float* data, FloatVector value)
    {
        std::memcpy(data, &value, sizeof(value));
    }

    inline void transposeRowsToColumns(
        FloatVector r0, FloatVector r1, FloatVector r2, FloatVector r3, FloatVector& c0, FloatVector& c1,
        FloatVector& c2, FloatVector& c3)
    {
        const FloatVector t0 = vec_mergeh(r0, r2);
        const FloatVector t1 = vec_mergel(r0, r2);
        const FloatVector t2 = vec_mergeh(r1, r3);
        const FloatVector t3 = vec_mergel(r1, r3);

        c0 = vec_mergeh(t0, t2);
        c1 = vec_mergel(t0, t2);
        c2 = vec_mergeh(t1, t3);
        c3 = vec_mergel(t1, t3);
    }

    inline osg::Vec3f transformAffinePoint(
        const FloatVector& c0, const FloatVector& c1, const FloatVector& c2, const FloatVector& c3,
        const osg::Vec3f& value)
    {
        const FloatVector x = vec_splats(value.x());
        const FloatVector y = vec_splats(value.y());
        const FloatVector z = vec_splats(value.z());
        const FloatVector result = vec_madd(c0, x, vec_madd(c1, y, vec_madd(c2, z, c3)));
        alignas(16) float output[4];
        storeFloatVector(output, result);
        return osg::Vec3f(output[0], output[1], output[2]);
    }

    inline osg::Vec3f transformDirection3x3(
        const FloatVector& c0, const FloatVector& c1, const FloatVector& c2, const osg::Vec3f& value)
    {
        const FloatVector x = vec_splats(value.x());
        const FloatVector y = vec_splats(value.y());
        const FloatVector z = vec_splats(value.z());
        const FloatVector result = vec_madd(c0, x, vec_madd(c1, y, c2 * z));
        alignas(16) float output[4];
        storeFloatVector(output, result);
        return osg::Vec3f(output[0], output[1], output[2]);
    }
#endif
}

namespace SceneUtil
{

    RigGeometry::RigGeometry()
    {
        setNumChildrenRequiringUpdateTraversal(1);
        // update done in accept(NodeVisitor&)
    }

    RigGeometry::RigGeometry(const RigGeometry& copy, const osg::CopyOp& copyop)
        : Drawable(copy, copyop)
        , mData(copy.mData)
    {
        setSourceGeometry(copy.mSourceGeometry);
        setNumChildrenRequiringUpdateTraversal(1);
    }

    void RigGeometry::setSourceGeometry(osg::ref_ptr<osg::Geometry> sourceGeometry)
    {
        for (unsigned int i = 0; i < 2; ++i)
            mGeometry[i] = nullptr;

        mSourceGeometry = sourceGeometry;

        for (unsigned int i = 0; i < 2; ++i)
        {
            const osg::Geometry& from = *sourceGeometry;

            // DO NOT COPY AND PASTE THIS CODE. Cloning osg::Geometry without also cloning its contained Arrays is
            // generally unsafe. In this specific case the operation is safe under the following two assumptions:
            // - When Arrays are removed or replaced in the cloned geometry, the original Arrays in their place must
            // outlive the cloned geometry regardless. (ensured by mSourceGeometry)
            // - Arrays that we add or replace in the cloned geometry must be explicitely forbidden from reusing
            // BufferObjects of the original geometry. (ensured by vbo below)
            mGeometry[i] = new osg::Geometry(from, osg::CopyOp::SHALLOW_COPY);
            mGeometry[i]->getOrCreateUserDataContainer()->addUserObject(new Resource::TemplateRef(mSourceGeometry));

            osg::Geometry& to = *mGeometry[i];
            to.setSupportsDisplayList(false);
            to.setUseVertexBufferObjects(true);
            to.setCullingActive(false); // make sure to disable culling since that's handled by this class
            to.setComputeBoundingBoxCallback(new CopyBoundingBoxCallback());
            to.setComputeBoundingSphereCallback(new CopyBoundingSphereCallback());

            // vertices and normals are modified every frame, so we need to deep copy them.
            // assign a dedicated VBO to make sure that modifications don't interfere with source geometry's VBO.
            osg::ref_ptr<osg::VertexBufferObject> vbo(new osg::VertexBufferObject);
            vbo->setUsage(GL_DYNAMIC_DRAW_ARB);

            osg::ref_ptr<osg::Array> vertexArray
                = static_cast<osg::Array*>(from.getVertexArray()->clone(osg::CopyOp::DEEP_COPY_ALL));
            if (vertexArray)
            {
                vertexArray->setVertexBufferObject(vbo);
                to.setVertexArray(vertexArray);
            }

            if (const osg::Array* normals = from.getNormalArray())
            {
                osg::ref_ptr<osg::Array> normalArray
                    = static_cast<osg::Array*>(normals->clone(osg::CopyOp::DEEP_COPY_ALL));
                if (normalArray)
                {
                    normalArray->setVertexBufferObject(vbo);
                    to.setNormalArray(normalArray, osg::Array::BIND_PER_VERTEX);
                }
            }

            if (const osg::Vec4Array* tangents = dynamic_cast<const osg::Vec4Array*>(from.getTexCoordArray(7)))
            {
                mSourceTangents = tangents;
                osg::ref_ptr<osg::Array> tangentArray
                    = static_cast<osg::Array*>(tangents->clone(osg::CopyOp::DEEP_COPY_ALL));
                tangentArray->setVertexBufferObject(vbo);
                to.setTexCoordArray(7, tangentArray, osg::Array::BIND_PER_VERTEX);
            }
            else
                mSourceTangents = nullptr;
        }
    }

    osg::ref_ptr<osg::Geometry> RigGeometry::getSourceGeometry() const
    {
        return mSourceGeometry;
    }

    bool RigGeometry::initFromParentSkeleton(osg::NodeVisitor* nv)
    {
        const osg::NodePath& path = nv->getNodePath();
        for (osg::NodePath::const_reverse_iterator it = path.rbegin() + 1; it != path.rend(); ++it)
        {
            osg::Node* node = *it;
            if (node->asTransform())
                continue;
            if (Skeleton* skel = dynamic_cast<Skeleton*>(node))
            {
                mSkeleton = skel;
                break;
            }
        }

        if (!mSkeleton)
        {
            Log(Debug::Error) << "Error: A RigGeometry did not find its parent skeleton";
            return false;
        }

        if (!mData)
        {
            Log(Debug::Error) << "Error: No influence data set on RigGeometry";
            return false;
        }

        mNodes.clear();
        for (const BoneInfo& info : mData->mBones)
        {
            mNodes.push_back(mSkeleton->getBone(info.mName));
            if (!mNodes.back())
                Log(Debug::Error) << "Error: RigGeometry did not find bone " << info.mName;
        }

        return true;
    }

    void RigGeometry::cull(osg::NodeVisitor* nv)
    {
        if (!mSkeleton)
        {
            Log(Debug::Error)
                << "Error: RigGeometry rendering with no skeleton, should have been initialized by UpdateVisitor";
            // try to recover anyway, though rendering is likely to be incorrect.
            if (!initFromParentSkeleton(nv))
                return;
        }

        unsigned int traversalNumber = nv->getTraversalNumber();
        if (mLastFrameNumber == traversalNumber || (mLastFrameNumber != 0 && !mSkeleton->getActive()))
        {
            osg::Geometry& geom = *getGeometry(mLastFrameNumber);
            nv->pushOntoNodePath(&geom);
            nv->apply(geom);
            nv->popFromNodePath();
            return;
        }
        mLastFrameNumber = traversalNumber;
        osg::Geometry& geom = *getGeometry(mLastFrameNumber);

        mSkeleton->updateBoneMatrices(traversalNumber);

        // skinning
        const osg::Vec3Array* positionSrc = static_cast<osg::Vec3Array*>(mSourceGeometry->getVertexArray());
        const osg::Vec3Array* normalSrc = static_cast<osg::Vec3Array*>(mSourceGeometry->getNormalArray());
        const osg::Vec4Array* tangentSrc = mSourceTangents;

        osg::Vec3Array* positionDst = static_cast<osg::Vec3Array*>(geom.getVertexArray());
        osg::Vec3Array* normalDst = static_cast<osg::Vec3Array*>(geom.getNormalArray());
        osg::Vec4Array* tangentDst = static_cast<osg::Vec4Array*>(geom.getTexCoordArray(7));

        std::vector<osg::Matrixf> boneMatrices(mNodes.size());
        std::vector<Bone*>::const_iterator bone = mNodes.begin();
        std::vector<BoneInfo>::const_iterator boneInfo = mData->mBones.begin();
        for (osg::Matrixf& boneMat : boneMatrices)
        {
            if (*bone != nullptr)
                boneMat = boneInfo->mInvBindMatrix * (*bone)->mMatrixInSkeletonSpace;
            ++bone;
            ++boneInfo;
        }

        osg::Matrixf transform;
        if (mSkinToSkelMatrix)
            transform = (*mSkinToSkelMatrix) * mData->mTransform;
        else
            transform = mData->mTransform;

        for (const auto& [influences, vertices] : mData->mInfluences)
        {
            osg::Matrixf resultMat(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);

#if defined(OPENMW_HAVE_ALTIVEC)
            FloatVector blendedRows[4] = {
                vec_splats(0.0f),
                vec_splats(0.0f),
                vec_splats(0.0f),
                vec_splats(0.0f),
            };
            const FloatVector affineMask = (__vector float){ 1.0f, 1.0f, 1.0f, 0.0f };

            for (const auto& [index, weight] : influences)
            {
                if (mNodes[index] == nullptr)
                    continue;
                const FloatVector weightVector = vec_splats(weight);
                const float* boneMatPtr = boneMatrices[index].ptr();
                for (int row = 0; row < 4; ++row)
                {
                    const FloatVector sourceRow = loadFloatVector(boneMatPtr + row * 4);
                    blendedRows[row] = vec_madd(sourceRow, weightVector * affineMask, blendedRows[row]);
                }
            }

            float* resultMatPtr = resultMat.ptr();
            for (int row = 0; row < 4; ++row)
                storeFloatVector(resultMatPtr + row * 4, blendedRows[row]);
            resultMatPtr[15] = 1.0f;
#else
            for (const auto& [index, weight] : influences)
            {
                if (mNodes[index] == nullptr)
                    continue;
                const float* boneMatPtr = boneMatrices[index].ptr();
                float* resultMatPtr = resultMat.ptr();
                for (int i = 0; i < 16; ++i, ++resultMatPtr, ++boneMatPtr)
                    if (i % 4 != 3)
                        *resultMatPtr += *boneMatPtr * weight;
            }
#endif

            resultMat *= transform;

#if defined(OPENMW_HAVE_ALTIVEC)
            FloatVector c0;
            FloatVector c1;
            FloatVector c2;
            FloatVector c3;
            const float* resultMatPtr = resultMat.ptr();
            transposeRowsToColumns(loadFloatVector(resultMatPtr), loadFloatVector(resultMatPtr + 4),
                loadFloatVector(resultMatPtr + 8), loadFloatVector(resultMatPtr + 12), c0, c1, c2, c3);

            for (unsigned short vertex : vertices)
            {
                (*positionDst)[vertex] = transformAffinePoint(c0, c1, c2, c3, (*positionSrc)[vertex]);
                if (normalDst)
                    (*normalDst)[vertex] = transformDirection3x3(c0, c1, c2, (*normalSrc)[vertex]);

                if (tangentDst)
                {
                    const osg::Vec4f& srcTangent = (*tangentSrc)[vertex];
                    const osg::Vec3f transformedTangent = transformDirection3x3(
                        c0, c1, c2, osg::Vec3f(srcTangent.x(), srcTangent.y(), srcTangent.z()));
                    (*tangentDst)[vertex] = osg::Vec4f(transformedTangent, srcTangent.w());
                }
            }
#else
            for (unsigned short vertex : vertices)
            {
                (*positionDst)[vertex] = resultMat.preMult((*positionSrc)[vertex]);
                if (normalDst)
                    (*normalDst)[vertex] = osg::Matrixf::transform3x3((*normalSrc)[vertex], resultMat);

                if (tangentDst)
                {
                    const osg::Vec4f& srcTangent = (*tangentSrc)[vertex];
                    osg::Vec3f transformedTangent = osg::Matrixf::transform3x3(
                        osg::Vec3f(srcTangent.x(), srcTangent.y(), srcTangent.z()), resultMat);
                    (*tangentDst)[vertex] = osg::Vec4f(transformedTangent, srcTangent.w());
                }
            }
#endif
        }

        positionDst->dirty();
        if (normalDst)
            normalDst->dirty();
        if (tangentDst)
            tangentDst->dirty();

        geom.osg::Drawable::dirtyGLObjects();

        nv->pushOntoNodePath(&geom);
        nv->apply(geom);
        nv->popFromNodePath();
    }

    void RigGeometry::updateBounds(osg::NodeVisitor* nv)
    {
        if (!mSkeleton)
        {
            if (!initFromParentSkeleton(nv))
                return;
        }

        if (!mSkeleton->getActive() && !mBoundsFirstFrame)
            return;
        mBoundsFirstFrame = false;

        mSkeleton->updateBoneMatrices(nv->getTraversalNumber());

        updateSkinToSkelMatrix(nv->getNodePath());

        osg::BoundingBox box;
        osg::Matrixf transform;
        if (mSkinToSkelMatrix)
            transform = (*mSkinToSkelMatrix) * mData->mTransform;
        else
            transform = mData->mTransform;

        size_t index = 0;
        for (const BoneInfo& info : mData->mBones)
        {
            const Bone* bone = mNodes[index++];
            if (bone == nullptr)
                continue;

            osg::BoundingSpheref bs = info.mBoundSphere;
            transformBoundingSphere(bone->mMatrixInSkeletonSpace * transform, bs);
            box.expandBy(bs);
        }

        if (box != _boundingBox)
        {
            _boundingBox = box;
            _boundingSphere = osg::BoundingSphere(_boundingBox);
            _boundingSphereComputed = true;
            for (unsigned int i = 0; i < getNumParents(); ++i)
                getParent(i)->dirtyBound();

            for (unsigned int i = 0; i < 2; ++i)
            {
                osg::Geometry& geom = *mGeometry[i];
                static_cast<CopyBoundingBoxCallback*>(geom.getComputeBoundingBoxCallback())->boundingBox = _boundingBox;
                static_cast<CopyBoundingSphereCallback*>(geom.getComputeBoundingSphereCallback())->boundingSphere
                    = _boundingSphere;
                geom.dirtyBound();
            }
        }
    }

    void RigGeometry::updateSkinToSkelMatrix(const osg::NodePath& nodePath)
    {
        if (mSkinToSkelMatrix)
            mSkinToSkelMatrix->makeIdentity();
        auto skeletonRoot = std::find(nodePath.begin(), nodePath.end(), mSkeleton);
        if (skeletonRoot == nodePath.end())
            return;
        skeletonRoot++;
        auto skinRoot = nodePath.end();
        if (!mData->mRootBone.empty())
            skinRoot = std::find_if(skeletonRoot, nodePath.end(),
                [&](const osg::Node* node) { return Misc::StringUtils::ciEqual(node->getName(), mData->mRootBone); });
        if (skinRoot == nodePath.end())
        {
            // Failed to find skin root, cancel out everything up till the trishape.
            // Our parent node is the trishape's transform
            skinRoot = nodePath.end() - 2;
            if ((*skinRoot)->getName() != getName()) // but maybe it can get optimized out
                skinRoot++;
        }
        else
            skinRoot++;
        for (auto it = skeletonRoot; it != skinRoot; ++it)
        {
            const osg::Node* node = *it;
            if (const osg::Transform* trans = node->asTransform())
            {
                const osg::MatrixTransform* matrixTrans = trans->asMatrixTransform();
                if (matrixTrans && matrixTrans->getMatrix().isIdentity())
                    continue;
                if (!mSkinToSkelMatrix)
                    mSkinToSkelMatrix = new osg::RefMatrix;
                trans->computeWorldToLocalMatrix(*mSkinToSkelMatrix, nullptr);
            }
        }
    }

    void RigGeometry::setBoneInfo(std::vector<BoneInfo>&& bones)
    {
        if (!mData)
            mData = new InfluenceData;

        mData->mBones = std::move(bones);
    }

    void RigGeometry::setInfluences(const std::vector<VertexWeights>& influences)
    {
        if (!mData)
            mData = new InfluenceData;

        std::unordered_map<unsigned short, BoneWeights> vertexToInfluences;
        size_t index = 0;
        for (const auto& influence : influences)
        {
            for (const auto& [vertex, weight] : influence)
                vertexToInfluences[vertex].emplace_back(index, weight);
            index++;
        }

        std::map<BoneWeights, VertexList> influencesToVertices;
        for (const auto& [vertex, weights] : vertexToInfluences)
            influencesToVertices[weights].emplace_back(vertex);

        mData->mInfluences.reserve(influencesToVertices.size());
        mData->mInfluences.assign(influencesToVertices.begin(), influencesToVertices.end());
    }

    void RigGeometry::setInfluences(const std::vector<BoneWeights>& influences)
    {
        if (!mData)
            mData = new InfluenceData;

        std::map<BoneWeights, VertexList> influencesToVertices;
        for (size_t i = 0; i < influences.size(); i++)
            influencesToVertices[influences[i]].emplace_back(static_cast<VertexList::value_type>(i));

        mData->mInfluences.reserve(influencesToVertices.size());
        mData->mInfluences.assign(influencesToVertices.begin(), influencesToVertices.end());
    }

    void RigGeometry::setTransform(osg::Matrixf&& transform)
    {
        if (!mData)
            mData = new InfluenceData;
        mData->mTransform = transform;
    }

    void RigGeometry::setRootBone(std::string_view name)
    {
        if (!mData)
            mData = new InfluenceData;
        mData->mRootBone = name;
    }

    void RigGeometry::accept(osg::NodeVisitor& nv)
    {
        if (!nv.validNodeMask(*this))
            return;

        nv.pushOntoNodePath(this);

        if (nv.getVisitorType() == osg::NodeVisitor::CULL_VISITOR)
        {
            // The cull visitor won't be applied to the node itself,
            // but we want to use its state to render the child geometry.
            osg::StateSet* stateset = getStateSet();
            osgUtil::CullVisitor* cv = static_cast<osgUtil::CullVisitor*>(&nv);
            if (stateset)
                cv->pushStateSet(stateset);

            cull(&nv);
            if (stateset)
                cv->popStateSet();
        }
        else if (nv.getVisitorType() == osg::NodeVisitor::UPDATE_VISITOR)
            updateBounds(&nv);
        else
            nv.apply(*this);

        nv.popFromNodePath();
    }

    void RigGeometry::accept(osg::PrimitiveFunctor& func) const
    {
        getGeometry(mLastFrameNumber)->accept(func);
    }

    osg::Geometry* RigGeometry::getGeometry(unsigned int frame) const
    {
        return mGeometry[frame % 2].get();
    }

}
